# AI 女友「小雅」— GX10 一鍵部署包

在 NVIDIA **GX10 / DGX Spark（GB10，aarch64）**上、全程本地跑一個會說話、會動嘴型的 AI 女友「小雅」：**語音辨識 → 大腦 → 語音合成 → 即時口型數字人**。全部在本機，斷網也能用、不花 API 錢。

> 語音完全**棓發為 `ref.wav` 的音色**（不是模型原生音），並用**繁體中文**回應。

---

## 架構（對應 huggingface `speech-to-speech`）

```
你的麥克風 → [STT: Paraformer] → [LLM: Qwen3.6-35B-A3B (本地 llama-server)]
          → [TTS: Qwen3-TTS + ref.wav 音色克隆] → [LiveTalking 口型] → 喇叭 + 小雅臉
```

| 階段 | 元件 | 埠 |
|---|---|---|
| Realtime 協定 | `speech-to-speech`（OpenAI Realtime over WS） | 8765 |
| 大腦 | llama.cpp `Qwen3.6-35B-A3B-Uncensored` Q4 | 8090 |
| 語音合成 | **Qwen3-TTS 12Hz-1.7B-Base**（`ref_audio` 克隆小雅） | — |
| 語音辨識 | Paraformer (FunASR，中文) | — |
| 數字人 | LiveTalking (wav2lip, WebRTC) | 8010 |
| 網頁 | hf-realtime-voice | 7860 |
| HTTPS | Caddy（mkcert CA） | 7861 |

---

## 硬體需求

- **GX10 / DGX Spark (GB10)**：121GB 統一記憶體，跑 35B-A3B + TTS + wav2lip 綽綽有餘。
- 磁碟：約 **60～80GB**（模型約 25GB+，含 LLM 21GB）。
- ✔️ 也可跑在一般 RTX 卡（≥16GB 顯存），LLM 改小一點即可（見「換更小模型」）。

---

## 一鍵安裝

```bash
# 在 GX10 上（asus 使用者，不需 sudo）
git clone <你的repo網址> ~/ai-girlfriend
cd ~/ai-girlfriend
./setup.sh          # 建 venv、裝依賴、下載模型、套用 patch、產生 HTTPS
```

> 網路慢請先設鏡像：`export HF_ENDPOINT=https://hf-mirror.com`
> 只重下模型：`./setup.sh --only-models`（或 `./install-models.sh`）

**安裝完成後**
```bash
./scripts/start-all.sh     # 用 tmux 一次啟動所有服務
```
瀏覽器開 **`https://<GX10-IP>:7861`**（先在瀏覽器安裝 `~/ai-gf/certs/rootCA.pem` 憑證，麥克風才能用）。

---

## 使用流程與介面（畫面）

### 網頁介面長什麼樣
開啟 `https://<GX10-IP>:7861` 後會看到一個網頁，主要元素：

- **中央圓形按鈕（TAP TO START）**：點它**開始／結束對話**（第一次會請求麥克風權限）。
- **右上角齒輪（Settings）**：打開設定面板，裡面有：
  - **Voice**：音色。不需改（我們已在後端**強制用 `ref.wav` 小雅克隆**，所以 Session 裡的 Voice 會被忽略）。
  - **Language**：語言（`auto` 即可）。
  - **Instructions**：人設。不需填（後端已**強制中文小雅人設**）。
  - **Mic / Speaker**：麥克風與喇叭，選你的實體裝置。
  - **NOISE GATE 滑塊**：**拉到最左（關閉）**，避免把語音切斷。
- **數字人畫面**：小雅（或你的女友照片）的臉，會隨語音即時動口型。

### 完整使用流程
1. **在瀏覽器安裝 CA 憑證**（`~/ai-gf/certs/rootCA.pem`，加入「信任的根憑證」），HTTPS 頁面才能用麥克風。
2. 用**有麥克風的電腦**開 `https://<GX10-IP>:7861`。
3. 點 **TAP TO START**，允許麥克風。
4. 在 Settings 確認 **Mic** 選到你的麥克風、**NOISE GATE 關閉**。
5. **用中文講話**（如「你好呀，我們聊聊吧」）。STT 是中文 paraformer，講英文它聽不懂。
6. 小雅會用**她的音色（`ref.wav` 克隆）**、**繁體中文**回應，同時**數字人臉會動口型**。

### 在 GX10 本機直接用（免憑證）
只要在 **GX10 本機**開瀏覽器，走 **`http://localhost:7860`** 即可，**完全不用 CA 憑證／認證**。

- **為什麼不用憑證**：瀏覽器規定麥克風只能在「安全上下文」用，而 **`localhost` 永遠被視為安全上下文**。所以在 GX10 本機用 `localhost:7860` 就符合安全上下文，麥克風可直接用，**不需要 HTTPS／CA 憑證**。
- **Caddy HTTPS（`:7861`＋CA 憑證）只給「從別台機器（如 Windows NB）連」時用**：因為區網 IP 用純 HTTP 不是安全上下文，麥克風會被擋。兩者互不影響。

**本機使用流程**
1. 在 GX10 的 Firefox 開 **`http://localhost:7860`**。
2. 點 **TAP TO START**，Firefox 會詢問麥克風權限 → 允許。
3. **※ 前提**：GX10 要有**實體麥克風＋喇叭**（通常需接一組 USB 音訊裝置；DGX Spark 盒子本身多半沒有內建麥克風/喇叭）。若要在 GX10 本機講話，請先接好 USB 麥克風／耳機，並在 Firefox 選到它。
4. Settings 裡確認 **Mic** 選到該 USB 麥克風、**NOISE GATE 關閉**。
5. 用中文講話，小雅就會回應。

> 若 GX10 只是當伺服器、你主要在 Windows NB 講話，那 GX10 不用接音訊裝置；NB 連 `https://192.168.1.153:7861` 需裝 CA 憑證（見下）。

### （手機／NB 遠端）連過來才需 CA 憑證
- 從其他機器（如你的 Windows NB）用 **`https://<GX10-IP>:7861`**。
- 先在該瀏覽器安裝 `~/ai-gf/certs/rootCA.pem`（加入「信任的根憑證」），麥克風才能用。

### 使用提示
- 🎧 **戴耳機最順**：避免喇叭聲音被麥克風收回，造成「你好呀」重複。
- 一句一句、清楚地講，VAD 才能正確分段。
- 若剛啟動回應較慢，等約 2 分鐘模型 warmup 完會更順。
- 換聲音＝換 `assets/ref.wav`；換人設＝改 `patches/apply-patches.py` 裡的中文字串。

---

## 重要修正（這個 repo 已經內建，別再踩坑）

1. **音色克隆**：`ref.wav` 必須是 **16kHz 單聲道 pcm**。若不是，clone 會靜默失敗、退回原生音。`setup.sh` 已自動轉換並備份 `ref_orig.wav`。
2. **採樣率**：`speech-to-speech` 把 TTS 輸出轉成 **16kHz**。前端 `AUDIO_SAMPLE_RATE` 必須是 **16000**，否則聲音變高 1.5 倍、聽起來像「另一個人」。（`setup-frontend.sh` 已修正。）
3. **session voice 覆寫**：前端 Settings 的 Voice（如 `Aiden`）會蓋掉你的克隆音色。`patches/apply-patches.py` 已強制改用 `ref_audio` 克隆。
4. **強制中文**：`patches/apply-patches.py` 已在 LLM 層強制加中文小雅人設，**無論瀏覽器送什麼都會用繁體中文回**。
5. **短話被丟棄**：VAD `--min_speech_ms` 太低會把「你好」當短音丟掉。已調成 250/300 ＋ `--thresh 0.55`。

---

## 疑難排解

| 症狀 | 原因 | 解決 |
|---|---|---|
| 聲音像別人/變高 | 前端採樣率非 16000 | 確認 `AUDIO_SAMPLE_RATE = 16_000` |
| 聲音是男聲/原生 | session voice 蓋掉克隆 | 確認已套用 `apply-patches.py`（強制 ref.wav） |
| 說短話沒反應 | VAD 太嚴 | `--min_speech_ms 250`、`--thresh 0.5` |
| 一直重複「你好呀」 | 回聲 | **戴耳機**或調低 `--thresh` |
| 說英文 | STT 是中文 | 請說中文（paraformer 只認中文） |
| 數字人不會動、2x2 conv 崩潰 | avatar 生成尺寸錯 | 用 LiveTalking 官方 `/avatar.html`（`img_size=256`）重生 |
| `address already in use` | 舊實例還佔著埠 | `pkill -f "speech-to-speech"` 清掉再啟動 |

---

## 換更小的大腦（低顯存機器）

把 `scripts/start-llama-server.sh` 的 `LLM_FILE` 換成例如 `Qwen3-8B-GGUF` 的 Q4_K_M，並把 `start-s2s.sh` 的 `--model_name` 對應改掉即可。

## 自訂

- **換聲音**：把 `assets/ref.wav` 換成你要克隆的音色（16kHz 單聲道），重跑 `setup.sh`。
- **換人設**：改 `patches/apply-patches.py` 裡的 `forced` 中文人設字串。
- **換臉**：用 LiveTalking `/avatar.html` 上傳新照片生成 avatar，再改 `start-lt.sh` 的 `AVATAR_ID`。

---

## 授權

隨附的 huggingface `speech-to-speech` 為 Apache-2.0；LLM/TTS/ASR 模型各有其授權（見 huggingface 頁面）。本部署腳本以 MIT 釋出。
