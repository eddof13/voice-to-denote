# voice-to-denote

Records a voice note on your phone → transcribes with Whisper → Claude classifies and structures it → drops into your Denote org-mode notes automatically.

**Routes to:**
- `~/notes/` — Denote note (timestamped org file with title, tags, front matter)
- `~/notes/todo.org` — task (`* TODO`)
- `~/notes/upcoming.org` — reminder with `SCHEDULED:` date

**Classification:** speak naturally or use explicit prefixes (`TODO`, `REMIND ME`). Claude infers intent either way.

---

## Requirements

- Mac with Homebrew
- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- [Keyboard Maestro](https://www.keyboardmaestro.com/)
- MEGA (or any cloud sync app) to get audio from phone to Mac

---

## Install

```bash
./setup-voice-to-denote.sh
```

This installs ffmpeg, pipx, and openai-whisper, and copies `voice-to-denote.sh` to `~/bin/`.

---

## Keyboard Maestro setup

1. Double-click `Voice to Denote.kmmacros` to import the macro
2. In MEGA (or your sync app), configure your phone's voice recordings folder to sync to `~/voice_notes`

The macro watches `~/voice_notes` for new files and runs the pipeline automatically.

---

## Usage

Record a voice note on your phone and save it to your synced folder. When it lands on your Mac, KM triggers automatically. You'll get a notification when it's done.

**Examples:**
- *"TODO migrate the users table to use UUIDs"* → task in `todo.org`
- *"Remind me to deploy on Friday"* → reminder with scheduled date in `upcoming.org`
- *"The reason we use read replicas is to avoid load on the primary during reports"* → Denote note

---

## File layout

| File | Purpose |
|---|---|
| `voice-to-denote.sh` | Main pipeline: transcribe → classify → write |
| `setup-voice-to-denote.sh` | One-time setup for a new machine |
| `Voice to Denote.kmmacros` | Keyboard Maestro macro (import by double-clicking) |

---

## Notes

- First run downloads the Whisper `base.en` model (~140MB), cached after that
- Audio files are moved to Trash after processing
- Whisper occasionally mishears proper nouns; Claude usually corrects from context
- Denote directory is hardcoded to `~/notes` — edit `NOTES_DIR` in `voice-to-denote.sh` to change it
