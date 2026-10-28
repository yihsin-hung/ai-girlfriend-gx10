# Contributing

Thanks for helping improve this AI-girlfriend deployment kit! 

## Before you open a PR
- Keep the setup scripts **portable**: use `$GF_BASE` (not hardcoded paths) so it still works on a different box.
- Make sure any new shell script passes `bash -n` and ideally `shellcheck`.
- Keep the voice-clone / sample-rate / forced-Chinese fixes idempotent (re-running setup must not double-apply).
- Update **both** the Chinese `README.md` and English `README.en.md` for any behavior change.

## Adding a dependency or model
- Add the model to `install-models.sh` (resumable download + a real, working URL; note the license).
- Note the license/provenance in the "Third-party resources & license notice" section of both READMEs.

## Reporting an issue
Include: your hardware (GX10/GB10 or other GPU + VRAM), the exact command run, and the full error log.
