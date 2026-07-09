# voice-to-denote

Records a voice note on your phone → transcribes with Whisper → an LLM classifies
and structures it → drops into your Denote org-mode notes (or forge project) automatically.

**LLM backends:** Claude Code CLI and/or Grok Build CLI. Default is `auto` (first
available: claude, then grok). Override with `VOICE_TO_DENOTE_LLM=claude|grok|auto`.

**Routes to:**
- `~/notes/` — Denote note (timestamped org file with title, tags, front matter)
- `~/notes/todo.org` — task (`* TODO`)
- `~/notes/upcoming.org` — reminder with `SCHEDULED:` date
- `~/forge/Active Projects/<name>/` — new Operator's Forge project (when you say so)

**Classification:** speak naturally or use explicit prefixes (`TODO`, `REMIND ME`,
or "new project…"). The model infers intent either way.

---

## Requirements

- Mac with Homebrew
- At least one of:
  - [Claude Code CLI](https://claude.ai/code) installed and authenticated
  - [Grok Build CLI](https://grok.x.ai/) (`grok` on PATH, e.g. `~/.grok/bin`)
- [Keyboard Maestro](https://www.keyboardmaestro.com/)
- MEGA (or any cloud sync app) to get audio from phone to Mac

---

## Install

```bash
./setup-voice-to-denote.sh
```

This installs ffmpeg, pipx, and openai-whisper, and copies scripts to `~/bin/`.

---

## Keyboard Maestro setup

1. Double-click `Voice to Denote.kmmacros` to import the macro
2. In MEGA (or your sync app), configure your phone's voice recordings folder to sync to `~/voice_notes`

The macro watches `~/voice_notes` for new files and runs the pipeline automatically.

Optional: set the backend for the KM shell step, e.g.

```bash
export VOICE_TO_DENOTE_LLM=grok
~/bin/voice-to-denote.sh "$KMVAR_TriggerValue"
```

---

## Usage

Record a voice note on your phone and save it to your synced folder. When it lands on your Mac, KM triggers automatically.

**Examples:**
- *"TODO migrate the users table to use UUIDs"* → task in `todo.org`
- *"Remind me to deploy on Friday"* → reminder with scheduled date in `upcoming.org`
- *"The reason we use read replicas is to avoid load on the primary during reports"* → Denote note
- *"New project: Bible Terminal research MVP"* → forge scaffold under `~/forge/Active Projects/`

---

## Config

| Variable | Values | Default | Used by |
|---|---|---|---|
| `VOICE_TO_DENOTE_LLM` | `auto`, `claude`, `grok` | `auto` | `voice-to-denote.sh` |
| `FORGE_AGENT` | `auto`, `claude`, `grok` | `auto` | `forge-open-session.sh` |

`auto` picks the first CLI found on `PATH` (claude, then grok). Ensure
`~/.grok/bin` and `/opt/homebrew/bin` are on `PATH` for KM (the scripts prepend them).

---

## File layout

| File | Purpose |
|---|---|
| `voice-to-denote.sh` | Main pipeline: transcribe → classify → write |
| `setup-voice-to-denote.sh` | One-time setup for a new machine |
| `sweep-voice-notes.sh` | Retry stuck files in `.processing` |
| `forge-open-session.sh` | Open a forge project session in Terminal (claude or grok) |
| `Voice to Denote.kmmacros` | Keyboard Maestro macro (import by double-clicking) |
| `Forge Sessions.kmmacros` | KM macros for forge open/close session |
| `Sweep Voice Notes.kmmacros` | KM sweeper for failed processing |

---

## Notes

- First run downloads the Whisper `base.en` model (~140MB), cached after that
- Audio files move to `~/voice_notes/processed/` after success; failures stay in `.processing` for the sweeper
- Whisper occasionally mishears proper nouns; the LLM usually corrects from context
- Denote directory is hardcoded to `~/notes` — edit `NOTES_DIR` in `voice-to-denote.sh` to change it
- New forge projects get `AGENTS.md` plus a `CLAUDE.md` → `AGENTS.md` symlink (model-agnostic Operator's Forge layout)
