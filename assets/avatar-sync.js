/* ============================================================================
 * avatar-sync.js  —  s2s 克隆音色 + LiveTalking 口型同步
 *
 * 替代 avatar-lite.js（状态切换版）。工作方式：
 *   1. 全屏 <video> 背景层接 LiveTalking 的 WebRTC 流
 *   2. 劫持 s2s 的 Realtime WebSocket，累积 response.output_audio.delta
 *   3. 吞掉 s2s 的本地播放（改由 LiveTalking 发声，保证音画同步）
 *   4. 回复结束 → 拼成 WAV → POST /humanaudio → 数字人开口
 *   5. 用户插话 → 打断 LiveTalking
 *
 * 安装：放到 hf-realtime-voice/ 目录，index.html 里把
 *       <script src="/avatar-lite.js"></script>
 *   换成
 *       <script src="/avatar-sync.js"></script>
 *   （必须在 main.js 之前）
 * ========================================================================== */
(function () {
  'use strict';

  const DEFAULTS = {
    // LiveTalking 地址。跨域被拦时改成 '/lt'（见文末反代方案）
    livetalkingBase: 'http://localhost:8010',

    // s2s 输出音频的采样率。实测 Qwen3-TTS 经 Realtime 通道输出为 16000。
    // 如果听起来像变声器（变调/变速），改成 24000 或 48000 试试。
    sampleRate: 16000,

    // 分块发送：累积多少毫秒音频就发一次（降低首响延迟）。
    // 0 = 等整段回复合成完再发（最稳，延迟最高）。
    // 建议先用 0 跑通，再试 1200 看有没有接缝杂音。
    chunkMs: 0,

    // 吞掉 s2s 自己的音频播放（必须开，否则会和 LiveTalking 双声）
    muteS2SAudio: true,

    // ---- 画面 ----
    fit: 'right',              // 'right' 竖版素材贴右；'cover' 16:9 铺满
    rightOffset: '-4%',
    objectPosition: '78% 50%',
    maskFade: 0.42,            // 左边缘淡入纯黑，0 = 关闭

    showStatus: true,          // 左下角状态条，调试期建议开着
    debug: true,
  };

  const U = window.AVATAR_CONFIG || {};
  const CFG = Object.assign({}, DEFAULTS, U);
  const log = (...a) => CFG.debug && console.log('%c[avatar]', 'color:#4ec9b0', ...a);
  const base = () => CFG.livetalkingBase.replace(/\/+$/, '');

  /* ---------------------------------------------------------------- 样式 */

  let maskCss = '';
  if (CFG.maskFade > 0) {
    const e = CFG.maskFade * 100;
    const g = `linear-gradient(90deg, rgba(0,0,0,0) 0%,` +
              ` rgba(0,0,0,.30) ${(e * 0.45).toFixed(1)}%,` +
              ` rgba(0,0,0,.85) ${(e * 0.78).toFixed(1)}%,` +
              ` #000 ${e.toFixed(1)}%)`;
    maskCss = `-webkit-mask-image:${g}; mask-image:${g};` +
              `-webkit-mask-size:100% 100%; mask-size:100% 100%;`;
  }

  const fitCss = CFG.fit === 'cover'
    ? `inset:0; width:100%; height:100%;
       object-fit:cover; object-position:${CFG.objectPosition};`
    : `top:0; right:${CFG.rightOffset}; height:100%; width:auto;
       max-width:none; object-fit:cover;`;

  const style = document.createElement('style');
  style.textContent = `
    html, body { background:#000 !important; }
    #av-layer {
      position:fixed; inset:0; z-index:0;
      background:#000; overflow:hidden; pointer-events:none;
      opacity:0; transition:opacity 1.1s ease;
    }
    #av-layer.live { opacity:1; }
    #av-video { position:absolute; ${fitCss} ${maskCss} display:block; }
    body > *:not(#av-layer) { position:relative; z-index:1; }
    #av-status {
      position:fixed; left:12px; bottom:12px; z-index:9999;
      font:11px/1.6 ui-monospace, monospace; color:#6b7280;
      background:rgba(0,0,0,.55); border:1px solid rgba(255,255,255,.08);
      border-radius:6px; padding:3px 8px; pointer-events:none;
    }
  `;
  (document.head || document.documentElement).appendChild(style);

  /* ---------------------------------------------------------------- DOM */

  let layer, video, audioEl, statusEl;

  function build() {
    layer = document.createElement('div');
    layer.id = 'av-layer';

    video = document.createElement('video');
    video.id = 'av-video';
    video.autoplay = true;
    video.playsInline = true;
    video.muted = true;          // 视频轨静音，声音走下面独立的 audio 元素
    video.setAttribute('muted', '');
    video.setAttribute('playsinline', '');
    layer.appendChild(video);

    audioEl = document.createElement('audio');
    audioEl.id = 'av-audio';
    audioEl.autoplay = true;

    document.body.insertBefore(layer, document.body.firstChild);
    document.body.appendChild(audioEl);

    if (CFG.showStatus) {
      statusEl = document.createElement('div');
      statusEl.id = 'av-status';
      document.body.appendChild(statusEl);
    }
    setStatus('idle');
  }

  function setStatus(s) {
    if (statusEl) statusEl.textContent = 'avatar: ' + s;
  }

  /* ------------------------------------------------------------- WebRTC */

  let pc = null, sessionid = 0, connecting = false;

  function waitIce(p) {
    if (p.iceGatheringState === 'complete') return Promise.resolve();
    return new Promise((res) => {
      const t = setTimeout(res, 3000);
      p.addEventListener('icegatheringstatechange', () => {
        if (p.iceGatheringState === 'complete') { clearTimeout(t); res(); }
      });
    });
  }

  async function connect() {
    if (pc || connecting) return;
    connecting = true;
    setStatus('connecting…');

    try {
      pc = new NativeRTC({
        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
      });

      pc.addTransceiver('video', { direction: 'recvonly' });
      pc.addTransceiver('audio', { direction: 'recvonly' });

      pc.ontrack = (e) => {
        if (e.track.kind === 'video') {
          video.srcObject = e.streams[0];
          video.play().catch(() => {});
          layer.classList.add('live');
        } else {
          audioEl.srcObject = e.streams[0];
          audioEl.play().catch((err) => log('音频自动播放被拦:', err.name));
        }
      };

      pc.onconnectionstatechange = () => {
        setStatus(pc.connectionState);
        if (['failed', 'closed', 'disconnected'].includes(pc.connectionState)) {
          layer.classList.remove('live');
          pc = null;
          setTimeout(connect, 3000);
        }
      };

      await pc.setLocalDescription(await pc.createOffer());
      await waitIce(pc);

      const r = await fetch(base() + '/offer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sdp: pc.localDescription.sdp,
          type: pc.localDescription.type,
        }),
      });
      if (!r.ok) throw new Error('offer HTTP ' + r.status);

      const ans = await r.json();
      if (ans.sessionid !== undefined) sessionid = ans.sessionid;
      await pc.setRemoteDescription(ans);

      log('已连接 LiveTalking, sessionid =', sessionid);
    } catch (err) {
      console.error('[avatar] 连接失败:', err);
      setStatus('失败: ' + err.message);
      pc = null;
      setTimeout(connect, 5000);
    } finally {
      connecting = false;
    }
  }

  /* -------------------------------------------------- PCM 累积 → WAV */

  let chunks = [];        // Uint8Array[]
  let bytes = 0;

  function b64ToBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function buildWav(parts, totalBytes, rate) {
    const buf = new ArrayBuffer(44 + totalBytes);
    const dv = new DataView(buf);
    const wstr = (off, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(off + i, s.charCodeAt(i)); };

    wstr(0, 'RIFF');
    dv.setUint32(4, 36 + totalBytes, true);
    wstr(8, 'WAVE');
    wstr(12, 'fmt ');
    dv.setUint32(16, 16, true);         // PCM chunk size
    dv.setUint16(20, 1, true);          // format = PCM
    dv.setUint16(22, 1, true);          // channels = mono
    dv.setUint32(24, rate, true);
    dv.setUint32(28, rate * 2, true);   // byte rate
    dv.setUint16(32, 2, true);          // block align
    dv.setUint16(34, 16, true);         // bits per sample
    wstr(36, 'data');
    dv.setUint32(40, totalBytes, true);

    const u8 = new Uint8Array(buf);
    let off = 44;
    for (const p of parts) { u8.set(p, off); off += p.length; }
    return new Blob([buf], { type: 'audio/wav' });
  }

  const bytesToMs = (b) => (b / 2) / CFG.sampleRate * 1000;

  function pushAudio(b64) {
    const u8 = b64ToBytes(b64);
    chunks.push(u8);
    bytes += u8.length;
    if (CFG.chunkMs > 0 && bytesToMs(bytes) >= CFG.chunkMs) flush();
  }

  async function flush() {
    if (!bytes) return;
    const parts = chunks, total = bytes;
    chunks = []; bytes = 0;

    const blob = buildWav(parts, total, CFG.sampleRate);
    log(`→ /humanaudio  ${(total / 1024).toFixed(0)} KB / ${bytesToMs(total).toFixed(0)} ms`);
    setStatus('speaking');

    try {
      const fd = new FormData();
      fd.append('file', blob, 'seg.wav');
      fd.append('sessionid', String(sessionid));
      const r = await fetch(base() + '/humanaudio', { method: 'POST', body: fd });
      if (!r.ok) log('humanaudio HTTP', r.status);
    } catch (err) {
      console.warn('[avatar] humanaudio 失败:', err);
    }
  }

  async function interrupt() {
    chunks = []; bytes = 0;
    setStatus('interrupt');
    for (const [path, body] of [
      ['/interrupt_talk', { sessionid }],
      ['/human', { text: '', type: 'echo', interrupt: true, sessionid }],
    ]) {
      try {
        const r = await fetch(base() + path, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        });
        if (r.ok) return;
      } catch (_) { /* 试下一个 */ }
    }
  }

  /* ------------------------------------------------- 劫持 s2s WebSocket */

  const NativeWS = window.WebSocket;
  const NativeRTC = window.RTCPeerConnection;   // 提前存好，避免被别处改写
  const isRealtime = (u) => typeof u === 'string' && u.includes('/v1/realtime');

  function onEvent(msg, evt) {
    const t = msg.type || '';

    // 助手音频增量 → 收走，不让前端播
    if (t === 'response.output_audio.delta' && typeof msg.delta === 'string') {
      pushAudio(msg.delta);
      if (CFG.muteS2SAudio) evt.stopImmediatePropagation();
      return;
    }

    // 一轮结束 → 把剩下的发出去
    if (t === 'response.done' || t === 'response.output_audio.done' ||
        t === 'output_audio_buffer.stopped') {
      flush();
      setStatus('idle');
      return;
    }

    // 用户开口 → 打断
    if (t === 'input_audio_buffer.speech_started') {
      setStatus('listening');
      interrupt();
    }
  }

  class PatchedWS extends NativeWS {
    constructor(url, protocols) {
      super(url, protocols);
      if (!isRealtime(url)) return;
      log('已挂载到 Realtime 连接');
      super.addEventListener('message', (evt) => {
        if (typeof evt.data !== 'string') return;
        let m; try { m = JSON.parse(evt.data); } catch (_) { return; }
        try { onEvent(m, evt); } catch (e) { console.warn('[avatar]', e); }
      });
    }
  }
  window.WebSocket = PatchedWS;

  /* ---------------------------------------------------------------- 启动 */

  function boot() {
    build();
    const kick = () => {
      document.removeEventListener('click', kick, true);
      document.removeEventListener('keydown', kick, true);
      connect();
    };
    document.addEventListener('click', kick, true);
    document.addEventListener('keydown', kick, true);
    log('已就绪，点击页面任意处连接数字人');
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();

  // 控制台调试
  window.AvatarSync = {
    connect, flush, interrupt, config: CFG,
    get sessionid() { return sessionid; },
    get pending() { return bytesToMs(bytes).toFixed(0) + 'ms'; },
    test: (txt) => fetch(base() + '/human', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: txt, type: 'echo', interrupt: false, sessionid }),
    }),
  };
})();
