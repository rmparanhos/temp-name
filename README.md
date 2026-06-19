# CHRIS

**C**oding-agent **H**ook **R**eview **I**nteractive **S**idekick.

A desktop companion (Rust + Tauri): when your coding agent (**GitHub Copilot
CLI** or **Claude Code**) is about to run a command, a little **blob** on your
screen reacts and you **approve or deny** it from a popup — without going back
to the terminal. It also pings you when a **Pull Request** needs your review,
and lets you approve it on the spot.

> Inspired by the **Claude Buddy** project, but **agnostic to the coding agent**
> (Copilot today, Claude Code, and Codex/others next) and built on **hooks**
> instead of wrapping the terminal.

---

## How it works

```
agent fires PreToolUse
   │ (payload on stdin, and waits)
   ▼
chris hook ──IPC (named pipe)──▶ companiond (Tauri)
   ▲                               blob reacts + approval popup
   └──────── decision ─────────────┘
```

- **Timeout** (you saw it but didn't answer) → **Deny** (safe).
- **Companion not running** (nobody saw it) → **Defer**: the agent falls back to
  its own native prompt, so you're never blocked nor unprotected.

---

## Get it running

### Option A — Prebuilt installer (Windows & macOS, easiest)

Once a release is published, go to the **Releases** page and download the
installer for your OS — **Windows** (`.msi` / `.exe`) or **macOS** (`.dmg`,
universal). Install, launch **CHRIS**, and skip to
[Connect it to a project](#connect-it-to-a-project). No Rust, no compiling.

> The macOS build is unsigned, so on first launch right-click the app → **Open**
> (or allow it in **System Settings → Privacy & Security**).

> Releases are produced automatically by GitHub Actions whenever a `v*` tag is
> pushed (see `.github/workflows/release.yml`).

### Option B — Build from source (one script)

You don't need to know Rust — the scripts install everything (Rust, build
tools, WebView2) and compile the project.

**Windows**

1. On this GitHub page: **`Code` → `Download ZIP`**, then extract.
2. Open the `scripts` folder and **double-click `setup.bat`** (the first build
   takes a while). It installs everything it needs, compiles, and then
   **launches CHRIS** automatically.
3. Next time, just **double-click `run.bat`** to start it again (keep that
   window open).

> **No admin needed.** `setup.bat` uses the MSVC linker if you already have it;
> otherwise it falls back to the **GNU toolchain + a portable MinGW** compiler
> downloaded into your user folder — so it works on locked-down machines without
> the Visual Studio C++ Build Tools.

**Linux / macOS**

```bash
./scripts/setup.sh     # installs everything and builds
./scripts/run.sh       # starts the companion (keep it open)
```

### Connect it to a project

**Windows:** double-click `scripts/connect.bat`, paste the path of the project
where you use the agent, and press Enter.

**Linux/macOS:** `./scripts/connect.sh /path/to/your/project`

This wires up **both Copilot CLI and Claude Code** (each in its own config file;
nothing is overwritten). Then just use the agent normally — when it wants to run
a command, the blob turns **orange** and the popup opens. Click **Allow** or
**Deny** (or `Esc` = deny).

> To wire only one: run `chris install --agent claude` (or `--agent copilot`)
> inside the project folder.

---

## Pull Request notifications

CHRIS also watches for **PRs that request your review**: the blob turns **blue**
and a popup shows the PR with **Open** (in the browser) and **Approve** (submits
an approving review) buttons.

To enable it, CHRIS needs a GitHub token — pick one:

- have the **GitHub CLI** logged in (`gh auth login`) — CHRIS picks the token up
  automatically; **or**
- set the `GITHUB_TOKEN` env var (scope `repo`) before launching.

Without a token, PR notifications are simply off (everything else still works).

---

## Characters & customizing

Hover the companion to get a small **character picker**: 🫧 blob, 🐱 cat,
🐶 dog, 😺 lucky cat. Your choice is remembered. It's **all SVG/PNG + CSS**, so
**no Rust required** to tweak or add one:

- `companiond/ui/index.html` — the SVG characters (blob, cat) and the picker.
- `companiond/ui/style.css` — colors and animations per state.
- `companiond/ui/sprites/<name>/` — PNG characters: one image per state
  (`idle/alert/approved/denied/pr.png`), like `dog` and `luckycat`.

Everything is driven by a single attribute, `data-state`
(`idle`, `alert`, `approved`, `denied`, `pr`). The daemon just calls
`setBlobState(state, count)` in `companiond/ui/blob.js`. To **add a PNG
character**, drop a folder under `sprites/`, list it in `PHOTO_SPRITES` +
`SPRITES`, and add a picker button. You can preview any change instantly by
opening `index.html` in a browser.

---

## Verify (for developers)

```bash
cargo test     # logic crates: core + transport + adapters + hook + github
```

The GUI app builds on any desktop machine (and in CI):

```bash
cargo run -p companiond
```

## Project layout

| Path | What it is |
|------|------------|
| `scripts/` | `setup` / `run` / `connect` for Windows & Unix |
| `companiond/` | The app: blob window, tray and popups (Tauri) |
| `crates/hook/` | The `chris` CLI (`hook` + `install`) |
| `crates/adapters/` | Translates each agent's payload ⇄ internal types |
| `crates/transport-ipc/` | IPC between `chris` and `companiond` |
| `crates/github/` | Pull Request polling & approve |
| `crates/core/` | The portable `no_std` "brain" (also compiles for ESP32) |
| `.github/workflows/` | CI (test + build) and Release (Windows & macOS installers) |

## Roadmap

**Done**

- ✅ Companion + system tray, approval popup (Enter = allow, Esc = deny).
- ✅ Hooks for **GitHub Copilot CLI** and **Claude Code**.
- ✅ **Pull Request notifications** (review requested) with open/approve.
- ✅ Multiple characters (blob, cat, dog, lucky cat) with a picker.
- ✅ Automated **Windows & macOS** installers via GitHub Actions.

**Next**

- ⏳ **Codex** adapter (and other agents).
- ⏳ "**Approve & remember**" — stop asking for actions you've already trusted.
- ⏳ Visible **queue** when several requests arrive at once.
- ⏳ **Gamification** — earn XP and keep streaks for reviewing PRs and handling
  approvals, unlock achievements/badges, and let the companion **level up and
  evolve** its look as you go.
- ⏳ Richer idle animation for the characters (e.g. Rive-based breathing —
  prototype kept on the `claude/rive-dog` branch).
- ⏳ A physical **ESP32 buddy** — a desk device with the sprite + Approve/Deny
  buttons (the `no_std` core is built for this).

## License

[MIT](LICENSE) © 2026 rmparanhos
