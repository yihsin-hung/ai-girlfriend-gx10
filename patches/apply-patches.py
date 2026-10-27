#!/usr/bin/env python3
"""Apply required patches to the installed speech_to_speech package.

Run with the speech-venv python:
    python patches/apply-patches.py
"""
import os, sys, shutil

SP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
def site_pkg():
    # locate speech_to_speech under any python site-packages on sys.path
    import speech_to_speech
    return os.path.dirname(os.path.dirname(speech_to_speech.__file__))

def patch_file(path, old, new, label):
    src = open(path, encoding="utf-8").read()
    n = src.count(old)
    if n == 0:
        print(f"[skip] {label}: pattern already applied or absent")
        return False
    if n > 1:
        print(f"[warn] {label}: pattern found {n} times, patching first")
    bak = path + ".baky"
    if not os.path.exists(bak):
        shutil.copy(path, bak)
    open(path, "w", encoding="utf-8").write(src.replace(old, new, 1))
    print(f"[ok]   {label}")
    return True

def main():
    base = site_pkg()
    tts = os.path.join(base, "speech_to_speech", "TTS", "qwen3_tts_handler.py")
    llm = os.path.join(base, "speech_to_speech", "LLM", "responses_api_language_model.py")

    # ------------------------------------------------------------------
    # 1) Force the configured ref_audio (Xiaoya clone). Ignore the
    #    frontend's session voice (e.g. 'Aiden') which otherwise overrides
    #    the clone reference and produces a male/native voice.
    old1 = """        if self._resolve_audio_path(session_voice) is not None:
            self.ref_audio = session_voice
            return

        logger.warning(
            "Ignoring Qwen3-TTS session voice override because it is not an audio file path: %r",
            session_voice,
        )"""
    new1 = """        # FORCED: ignore session voice override, keep the configured ref_audio clone.
        logger.info(
            "Qwen3-TTS: ignoring session voice override %r - using configured ref_audio clone.", session_voice,
        )
        return"""
    patch_file(tts, old1, new1, "qwen3_tts_handler._apply_session_voice_override")

    # ------------------------------------------------------------------
    # 2) Force a Chinese (Xiaoya) system prompt so the LLM always replies
    #    in Traditional Chinese regardless of what the frontend sends.
    old2 = """        if instructions:
            full_instructions = build_voice_system_prompt(instructions)
            chat.add_item(make_system_message(full_instructions))"""
    new2 = """        forced = ("你是「小雅」，他的女朋友，一个温柔黏人的台湾妹子。"
                  "无论他用什么语言，你都要用繁体中文（台湾用语）回应，绝对不要说英文。"
                  "说话口语、简短、亲切，常带语气词（呀、耶、嗯、啦）。"
                  "不要用 Markdown、列表、编号或表情符号。用「你」称呼他。")
        base = instructions if instructions else ""
        combined = forced + ((" " + base) if base else "")
        full_instructions = build_voice_system_prompt(combined)
        chat.add_item(make_system_message(full_instructions))"""
    patch_file(llm, old2, new2, "responses_api_language_model._apply_config (force zh)")
    print("done.")

if __name__ == "__main__":
    main()
