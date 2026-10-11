# 🌱 Code-Break

A CLI agent for the Hacktoberfest 2026 **Touch Grass** challenge. It watches the
files you save, notices when you have been coding too long (or are furiously
saving while stuck on a bug), and interrupts you:

1. **Groq** (using the blazing-fast **Mixtral** model) writes a short, witty "go
   outside" command.
2. **ElevenLabs** says it out loud.
3. The CLI pauses and asks **"What unique thing did you see outside?"**
4. Groq checks that your answer sounds like a real outdoor observation.
5. If it does, your **GitHub profile README** streak is bumped:
   `Touch Grass 🌱 Streak: X Days`.

```text
code_break/
├── bin/code_break.dart              # entry point (command runner)
├── lib/
│   ├── code_break.dart              # public exports
│   └── src/
│       ├── config.dart              # .env + environment variables
│       ├── errors.dart              # ServiceException & friends
│       ├── commands/
│       │   ├── watch_command.dart   # `watch`      - the main loop
│       │   ├── break_now_command.dart # `break-now` - run a break immediately
│       │   └── doctor_command.dart  # `doctor`     - check your setup
│       ├── services/
│       │   ├── activity_monitor.dart  # pure "is a break due?" logic
│       │   ├── watcher_service.dart   # `watcher` package wrapper
│       │   ├── groq_service.dart      # Groq: message + validation (Mixtral)
│       │   ├── elevenlabs_service.dart# text-to-speech
│       │   ├── audio_service.dart     # plays the mp3 (macOS/Windows/Linux)
│       │   ├── github_service.dart    # profile README read + commit
│       │   └── break_flow.dart        # orchestrates one full break
│       └── utils/
│           ├── readme_streak.dart   # pure streak parsing/incrementing
│           ├── console_input.dart   # async stdin line reader
│           ├── http_utils.dart      # friendly network errors
│           └── logger.dart          # coloured terminal output
├── test/                            # unit tests (streak, monitor, config)
├── .vscode/                         # launch + build tasks
├── .env.example
└── pubspec.yaml
```

## 1. Prerequisites

| Tool | Why | Get it |
| --- | --- | --- |
| Dart SDK 3.5+ | build and run | <https://dart.dev/get-dart> |
| VS Code + **Dart** extension | editing, running, compiling | Extensions panel → "Dart" |
| Groq account | blazing fast AI generation | <https://console.groq.com> |
| ElevenLabs account | voice (optional) | <https://elevenlabs.io> |
| GitHub account + profile README repo | streak (optional) | repo named exactly like your username |

Voice and streak are optional: without a key/token Code-Break still interrupts
you, it just stays silent / skips the GitHub update.

## 2. API keys

**Groq** - Go to [console.groq.com](https://console.groq.com) → *API Keys* → Create a new API key. We use the `mixtral-8x7b-320k` model which is free and natively supports JSON outputs.

**ElevenLabs** - elevenlabs.io → *Developers / API Keys* → create a key. 
*Note for Free Tier Users:* You **cannot** use custom community voices (Voice Library). Go to the *Voices* page, select a **Default / Premade** voice (like Alice), and copy its Voice ID.

**GitHub** - you need a repo named exactly like your username (e.g.
`octocat/octocat`) with a `README.md`. Then create a token:

* *Fine-grained token (recommended)*: Settings → Developer settings → Personal
  access tokens → Fine-grained → **Only select repositories** → pick your
  profile repo → Repository permissions → **Contents: Read and write**.
* *Classic token*: scope `public_repo` (the profile repo is public).

## 3. Configure `.env`

```bash
cp .env.example .env      # Windows: copy .env.example .env
```

```ini
# Groq API Key (Replaces Ollama)
GROQ_API_KEY=gsk_...

# ElevenLabs (Voice)
ELEVENLABS_API_KEY=sk_...
ELEVENLABS_VOICE_ID=Xb7hH8MSALEjdMEXNKf2
ELEVENLABS_MODEL_ID=eleven_multilingual_v2

# GitHub (Streak)
GITHUB_TOKEN=github_pat_...
GITHUB_USERNAME=shan2003034
```

Lookup order: real environment variables → `--env-file <path>` → `./.env` →
`.env` next to the compiled binary → `~/.code_break.env`. `.env` is git-ignored;
never commit it.

## 4. Run it from VS Code

1. Open the `code_break` folder, then **Terminal → New Terminal**.
2. `dart pub get`
3. `dart run bin/code_break.dart doctor` - checks Groq, ElevenLabs, GitHub.
4. `dart run bin/code_break.dart break-now` - plays one full break right away.
5. `dart run bin/code_break.dart watch --demo` - tiny thresholds (1 minute, or 5
   saves in 30 s). Save a few files in the folder and watch it trigger.

You can also press **F5** and pick one of the *Code-Break* launch
configurations. They use the integrated terminal on purpose: the "what did you
see?" prompt needs real keyboard input, which the Debug Console cannot give.

Run the tests with `dart test`.

## 5. Compile a standalone executable

In VS Code: **Terminal → Run Build Task…** (`Ctrl/Cmd+Shift+B`) →
*Code-Break: compile executable*. Or by hand:

```bash
dart pub get
dart compile exe bin/code_break.dart -o build/code_break          # macOS / Linux
dart compile exe bin/code_break.dart -o build\code_break.exe      # Windows
```

The binary has no Dart dependency. Put it on your `PATH` and keep your secrets in
`~/.code_break.env` (or next to the binary), then from any project:

```bash
cd ~/projects/my-app
code_break                 # same as: code_break watch
```

"Background" use: leave `code_break watch` running in a spare terminal tab (VS
Code's integrated terminal works well). It has to stay attached to a terminal
because the break is interactive.

## 6. Commands and options

```
code_break [--env-file <path>] [--verbose] <command>

watch       Watch a directory and interrupt you when you code for too long
break-now   Trigger a Touch Grass break right now (demo / setup test)
doctor      Check Groq, ElevenLabs and GitHub configuration
```

`watch` options (defaults in brackets):

| Option | Meaning |
| --- | --- |
| `--dir <path>` | directory to watch [current directory] |
| `--marathon <min>` | continuous coding before a break [50] |
| `--idle-reset <min>` | a pause this long counts as a real break [5] |
| `--burst-saves <n>` / `--burst-window <sec>` | "stuck on a bug": n saves within the window [20 / 120] |
| `--cooldown <min>` | quiet time after a completed break [20] |
| `--demo` | tiny thresholds for demos |
| `--no-voice` | skip ElevenLabs |

Global options go **before** the command: `code_break --verbose watch --demo`.

## 7. How the pieces work

* **Trigger** - every save (add/modify, deduplicated, with `.git`, `build`,
  `node_modules`, temp files... ignored) goes to `ActivityMonitor`. A *marathon*
  fires when a session (gaps shorter than `--idle-reset`) reaches `--marathon`
  minutes; *frantic* fires on `--burst-saves` saves within `--burst-window`.
* **Groq AI** - `POST /openai/v1/chat/completions` using `mixtral-8x7b-320k`. The verdict request uses
  `response_format: { "type": "json_object" }` to guarantee a strictly formatted `{"valid": true, "reason": "..."}` response. If the API fails, the break still happens with a built-in message.
* **Voice** - `POST /v1/text-to-speech/{voice_id}` returns MP3 bytes, written to
  a temp file and played with `afplay` (macOS), PowerShell's MediaPlayer
  (Windows) or `mpv`/`ffplay`/`mpg123`/`cvlc`/`play` (Linux). The temp file is
  deleted afterwards.
* **Streak** - `GET /repos/{u}/{u}/readme` → bump the counter → `PUT
  /repos/{u}/{u}/contents/{path}` (a normal commit on your default branch).
  The line is written as
  `Touch Grass 🌱 Streak: 5 Days <!-- touch-grass:last=2026-10-11 -->`; the
  invisible date marker prevents counting a day twice and resets the streak
  after a missed day. If your README has no counter, a `## 🌱 Touch Grass`
  section is appended. If it already has a plain `Touch Grass 🌱 Streak: N Days`
  line, that line is upgraded in place.

## 8. Troubleshooting

* **Groq HTTP 400/404 (Model not found/JSON format error)** - Some models do not support JSON outputs or are decommissioned. Ensure `GROQ_API_KEY` is valid and the model is set to `mixtral-8x7b-320k` in `groq_service.dart`.
* **ElevenLabs HTTP 402 (Free users cannot use library voices)** - Your free account cannot access Community Library voices. Go to ElevenLabs, choose a "Default" voice (e.g., Alice), and update `ELEVENLABS_VOICE_ID` in `.env`.
* **GitHub HTTP 403 (Resource not accessible / Read-only)** - Your Token lacks write permissions, or your profile repository is archived. Ensure the token has **Contents: Read and write** enabled, and unarchive the repository from GitHub Settings.
* **No sound on Linux** - install `mpv` (`sudo apt install mpv`). On WSL there is
  usually no audio device.
* **Nothing triggers** - run with `--verbose` to see every counted save, or use
  `--demo`.