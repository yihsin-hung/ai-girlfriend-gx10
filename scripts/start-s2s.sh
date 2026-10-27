#!/usr/bin/env bash
# Start the speech-to-speech realtime server (STT -> LLM -> TTS) on port 8765.
set -euo pipefail
GF_BASE="${GF_BASE:-$HOME/ai-gf}"
VENV="$GF_BASE/speech-venv"
export PATH="$GF_BASE/bin:$PATH"
export HF_HOME="${HF_HOME:-$GF_BASE/hf_home}"

exec "$VENV/bin/speech-to-speech" \
  --mode realtime \
  --num_pipelines 2 \
  --stt paraformer \
  --paraformer_stt_model_name "$GF_BASE/models/funasr/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch" \
  --paraformer_stt_device cuda \
  --language zh \
  --llm_backend responses-api \
  --model_name Qwen3-14B \
  --responses_api_base_url "http://localhost:${LLM_PORT:-8090}/v1" \
  --responses_api_api_key dummy \
  --responses_api_disable_thinking \
  --tts qwen3 \
  --qwen3_tts_model_name "$GF_BASE/models/qwen-tts/Qwen3-TTS-12Hz-1.7B-Base" \
  --qwen3_tts_language Chinese \
  --qwen3_tts_ref_audio "$GF_BASE/setup/ref.wav" \
  --qwen3_tts_ref_text "靠杯了，你终于上线了，我既开心又有点怨你，嗯；小雅一个人在这里等你，等的都快委屈死了！" \
  --thresh 0.55 --min_speech_ms 300 --min_silence_ms 1200 \
  --speech_pad_ms 300 --speculative_reopen_ms 2500 \
  --short_segment_merge_ms 800 --min_speech_continuation_ms 192
