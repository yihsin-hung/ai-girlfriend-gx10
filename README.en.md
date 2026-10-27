# AI Girlfriend "Xiaoya" — One-click GX10 Deployment Kit

A fully-local AI girlfriend named **Xiaoya** that runs on an NVIDIA **GX10 / DGX Spark (GB10, aarch64)**: speech recognition → LLM → speech synthesis → real-time lip-sync digital human. Everything runs on the box — works offline, no API costs.

> The voice is **cloned from `ref.wav`** (not the model's native voice), and she replies in **Traditional Chinese**.

There is also a [Chinese-language README](README.md).

---

## Architecture (backed by huggingface `speech-to-speech`)

```
Your mic → [STT: Paraformer] → [LLM: Qwen3.6-35B-A3B (local llama-server)]
        → [TTS: Qwen3-TTS + ref.wav voice clone] → [LiveTalking lip-sync] → Speaker + Xiaoya's face
```

| Stage | Component | Port |
|---|---|---|
| Realtime protocol | `speech-to-speech` (OpenAI Realtime over WS) | 8765 |
| Brain | llama.cpp `Qwen3.6-35B-A3B-Uncensored` Q4 | 8090 |
| TTS | **Qwen3-TTS 12Hz-1.7B-Base** (`ref_audio` clone of Xiaoya) | — |
| STT | Paraformer (FunASR, Chinese) | — |
| Digital human | LiveTalking (wav2lip, WebRTC) | 8010 |
| Web frontend | hf-realtime-voice | 7860 |
| HTTPS | Caddy (mkcert CA) | 7861 |

---

## Hardware requirements

- **GX10 / DGX Spark (GB10)**: 121 GB unified memory — runs the 35B-A3B + TTS + wav2lip comfortably.
- Disk: about **60–80 GB** (models ≈ 25 GB+ including the 21 GB LLM).
- ✔️ Also works on a regular RTX card (≥16 GB VRAM); use a smaller LLM (see "Use a smaller model").

---

## One-click install

```bash
# On the GX10 (as user `asus`, no sudo needed)
git clone <your-repo-url> ~/ai-girlfriend
cd ~/ai-girlfriend
./setup.sh          # create venvs, install deps, download models, apply patches, set up HTTPS
```

> Slow network? Set a mirror first: `export HF_ENDPOINT=https://hf-mirror.com`
> Re-download models only: `./setup.sh --only-models` (or `./install-models.sh`)

**After install**
```bash
./scripts/start-all.sh     # start all services at once via tmux
```
Open **`https://<GX10-IP>:7861`** (install `~/ai-gf/certs/rootCA.pem` in the browser first so the mic works).

---

## Usage flow & UI

### What the page looks like
Opening `https://<GX10-IP>:7861` shows a page with:

- **Center circular button (TAP TO START)**: click to **start / stop the conversation** (requests mic permission the first time).
- **Gear (Settings) in the top-right**: opens the settings panel with:
  - **Voice**: no need to change (the backend already **forces the `ref.wav` Xiaoya clone**, so the session Voice is ignored).
  - **Language**: `auto` is fine.
  - **Instructions**: no need to fill (backend already **forces the Chinese Xiaoya persona**).
  - **Mic / Speaker**: pick your real devices.
  - **NOISE GATE slider**: drag **all the way left (off)** so it doesn't cut your speech.
- **Digital human**: Xiaoya's (or your girlfriend's photo) face, moving lips in real time.

### Full usage flow
1. **Install the CA cert in your browser** (`~/ai-gf/certs/rootCA.pem`, add to trusted root certs) so the HTTPS page can use the mic.
2. From a **machine with a mic**, open `https://<GX10-IP>:7861`.
3. Click **TAP TO START**, allow the mic.
4. In Settings confirm your **Mic** is selected and **NOISE GATE is off**.
5. **Speak Chinese** (e.g. "你好呀，我們聊聊吧"). The STT is a Chinese Paraformer; it won't understand English.
6. Xiaoya replies in **her voice (cloned from `ref.wav`)** and **Traditional Chinese**, and the **digital human moves its lips**.

### Using directly on the GX10 (no certificate)
Just open the browser **on the GX10** at **`http://localhost:7860`** — **no CA cert / auth needed**.

- **Why no cert**: browsers only allow the mic in a "secure context", and **`localhost` is always a secure context**. So on the GX10, `localhost:7860` is already secure — the mic works without HTTPS/CA.
- **Caddy HTTPS (`:7861` + CA) is only needed when connecting from another machine (e.g. your Windows laptop)**, because a plain-HTTP LAN IP is not a secure context and the mic is blocked. The two don't conflict.

**On-box flow**
1. On the GX10, open **`http://localhost:7860`** in Firefox.
2. Click **TAP TO START**, allow mic permission.
3. **Prerequisite**: the GX10 needs a **physical mic + speaker** (usually a USB audio device; the DGX Spark box itself typically has none). If you want to talk on the GX10, plug in USB mic / headphones and select it in Firefox.
4. In Settings confirm the **Mic** is the USB device and **NOISE GATE is off**.
5. Speak Chinese; Xiaoya replies.

> If the GX10 is just the server and you talk on your Windows laptop, the GX10 doesn't need audio devices; the laptop connects to `https://192.168.1.153:7861` and needs the CA cert.

### Remote (phone / laptop) — CA cert required
- From another machine (e.g. your Windows laptop) use **`https://<GX10-IP>:7861`**.
- Install `~/ai-gf/certs/rootCA.pem` in that browser (trusted root certs) for the mic.

### Tips
- 🎧 **Headphones work best**: avoids the speaker's sound being picked up by the mic, which makes "你好呀" repeat.
- Speak one clear sentence at a time; the VAD segments properly.
- Right after startup responses can be slow — wait ~2 min for model warmup.
- Change the voice = replace `assets/ref.wav`; change the persona = edit the Chinese string in `patches/apply-patches.py`.

---

## Important fixes (already built into this repo — don't re-introduce these bugs)

1. **Voice cloning**: `ref.wav` MUST be **16 kHz mono pcm**. Otherwise cloning silently fails and falls back to the native voice. `setup.sh` already converts it and backs up `ref_orig.wav`.
2. **Sample rate**: `speech-to-speech` converts the TTS output to **16 kHz**. The frontend `AUDIO_SAMPLE_RATE` must be **16000**, otherwise the voice plays 1.5x high and sounds like "another person". (`setup-frontend.sh` already fixes it.)
3. **Session voice override**: the frontend's Voice (e.g. `Aiden`) overrides your clone. `patches/apply-patches.py` already forces the `ref_audio` clone.
4. **Force Chinese**: `patches/apply-patches.py` already adds a Chinese Xiaoya persona at the LLM layer, so it **always replies in Traditional Chinese** regardless of what the browser sends.
5. **Short speech dropped**: a low VAD `--min_speech_ms` drops short utterances like "你好". Already set to 250/300 with `--thresh 0.55`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Voice sounds like someone else / high | frontend sample rate not 16000 | ensure `AUDIO_SAMPLE_RATE = 16_000` |
| Voice is male / native | session voice overrides clone | ensure `apply-patches.py` applied (forces ref.wav) |
| No reply to short speech | VAD too strict | `--min_speech_ms 250`, `--thresh 0.5` |
| "你好呀" keeps repeating | echo | **wear headphones**, or lower `--thresh` |
| Replies in English | STT is Chinese | speak Chinese (Paraformer only understands Chinese) |
| Avatar doesn't move / 2x2-conv crash | wrong avatar size | regenerate via LiveTalking `/avatar.html` (`img_size=256`) |
| `address already in use` | stale instance holds the port | `pkill -f "speech-to-speech"` then restart |

---

## Use a smaller model (low-VRAM machines)

In `scripts/start-llama-server.sh` change `LLM_FILE` to e.g. `Qwen3-8B-GGUF` Q4_K_M, and update `--model_name` in `start-s2s.sh` accordingly.

## Customization

- **Change the voice**: replace `assets/ref.wav` with the voice you want to clone (16 kHz mono), rerun `setup.sh`.
- **Change the persona**: edit the `forced` Chinese string in `patches/apply-patches.py`.
- **Change the face**: upload a new photo via LiveTalking `/avatar.html`, then change `AVATAR_ID` in `start-lt.sh`.

---

## License

The bundled huggingface `speech-to-speech` is Apache-2.0; the LLM/TTS/ASR models have their own licenses (see each Hugging Face page). These deployment scripts are released under MIT.
