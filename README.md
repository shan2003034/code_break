# 🌱 Code-Break

A CLI agent for the Hacktoberfest 2026 **Touch Grass** challenge. It watches the
files you save, notices when you have been coding too long (or are furiously
saving while stuck on a bug), and interrupts you:

1. **Gemma** (running locally through **Ollama**) writes a short, witty "go
   outside" command.
2. **ElevenLabs** says it out loud.
3. The CLI pauses and asks **"What unique thing did you see outside?"**
4. Gemma checks that your answer sounds like a real outdoor observation.
5. If it does, your **GitHub profile README** streak is bumped:
   `Touch Grass 🌱 Streak: X Days`.

```
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
│       │   ├── ollama_service.dart    # Gemma: message + validation
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
| Ollama | runs Gemma locally | <https://ollama.com/download> |
| ElevenLabs account | voice (optional) | <https://elevenlabs.io> |
| GitHub account + profile README repo | streak (optional) | repo named exactly like your username |

Voice and streak are optional: without a key/token Code-Break still interrupts
you, it just stays silent / skips the GitHub update.

## 2. Ollama + Gemma

```bash
ollama pull gemma        # downloads the model once
ollama serve             # only if the Ollama app is not already running
curl http://localhost:11434/api/tags   # should list "gemma"
```

Newer Gemma generations work too: `ollama pull gemma3` and set
`OLLAMA_MODEL=gemma3` in `.env`.

## 3. API keys

**ElevenLabs** - elevenlabs.io → *Developers / API Keys* → create a key. If you
restrict the key, give it the **Text to Speech** permission. Optionally copy a
voice ID from the *Voices* page.

**GitHub** - you need a repo named exactly like your username (e.g.
`octocat/octocat`) with a `README.md`. Then create a token:

* *Fine-grained token (recommended)*: Settings → Developer settings → Personal
  access tokens → Fine-grained → **Only select repositories** → pick your
  profile repo → Repository permissions → **Contents: Read and write**.
* *Classic token*: scope `public_repo` (the profile repo is public).

## 4. Configure `.env`

```bash
cp .env.example .env      # Windows: copy .env.example .env
```

```ini
OLLAMA_HOST=http://localhost:11434
OLLAMA_MODEL=gemma
ELEVENLABS_API_KEY=xi-...
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM
GITHUB_TOKEN=github_pat_...
GITHUB_USERNAME=            # optional, looked up from the token
```

Lookup order: real environment variables → `--env-file <path>` → `./.env` →
`.env` next to the compiled binary → `~/.code_break.env`. `.env` is git-ignored;
never commit it.

## 5. Run it from VS Code

1. Open the `code_break` folder, then **Terminal → New Terminal**.
2. `dart pub get`
3. `dart run bin/code_break.dart doctor` - checks Ollama, ElevenLabs, GitHub.
4. `dart run bin/code_break.dart break-now` - plays one full break right away.
5. `dart run bin/code_break.dart watch --demo` - tiny thresholds (1 minute, or 5
   saves in 30 s). Save a few files in the folder and watch it trigger.

You can also press **F5** and pick one of the *Code-Break* launch
configurations. They use the integrated terminal on purpose: the "what did you
see?" prompt needs real keyboard input, which the Debug Console cannot give.

Run the tests with `dart test`.

## 6. Compile a standalone executable

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

## 7. Commands and options

```
code_break [--env-file <path>] [--verbose] <command>

watch       Watch a directory and interrupt you when you code for too long
break-now   Trigger a Touch Grass break right now (demo / setup test)
doctor      Check Ollama, ElevenLabs and GitHub configuration
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

## 8. How the pieces work

* **Trigger** - every save (add/modify, deduplicated, with `.git`, `build`,
  `node_modules`, temp files... ignored) goes to `ActivityMonitor`. A *marathon*
  fires when a session (gaps shorter than `--idle-reset`) reaches `--marathon`
  minutes; *frantic* fires on `--burst-saves` saves within `--burst-window`.
* **Gemma** - `POST /api/generate` with `stream: false`. The verdict request uses
  `format: "json"`, treats your answer strictly as data (angle brackets
  stripped, instructions ignored) and expects `{"valid": true, "reason": "..."}`.
  If Ollama is down, the break still happens with a built-in message.
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

## 9. Troubleshooting

* **"Could not reach Ollama"** - start it (`ollama serve` or open the app).
* **"Model gemma is not installed"** - `ollama pull gemma` (or fix `OLLAMA_MODEL`).
* **No sound on Linux** - install `mpv` (`sudo apt install mpv`). On WSL there is
  usually no audio device.
* **GitHub 404** - the repo `<username>/<username>` must exist and the token must
  include it with *Contents: Read and write*.
* **Nothing triggers** - run with `--verbose` to see every counted save, or use
  `--demo`.
* **Many files on Linux** - if the watcher fails with an inotify error, raise
  `fs.inotify.max_user_watches`, or point `--dir` at a smaller folder.
