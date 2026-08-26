# Virtual PC Experiment

**An experiment log for building a browser-only "Ubuntu virtual PC" with no GPU and no local Docker**

A personal project and how-to guide for running a full KDE Plasma desktop on top of
GitHub Codespaces (free tier), reachable entirely from a browser — including
Windows apps (via Wine) and Roblox Studio.

- No way to install Docker on the local PC
- No PC capable of running Roblox Studio

This experiment started from those two constraints, with the thought: "then why not
just run it from a browser?"

> ⚠️ This is a personal experiment log, not a guarantee of stable production use.
> It assumes the GitHub Codespaces free tier (120 core-hours/month on a personal account).

### ⚠️ About GitHub's Terms of Service (Important)

Please read this before trying this project.

GitHub's official terms ([GitHub Terms for Additional Products and Features](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features), Codespaces section) explicitly prohibit, among other things (summarized):

- Cryptomining
- Disrupting, or attempting to gain unauthorized access to, any other service, device, data, account, or network
- Offering Codespaces itself (or any part of it) as a stand-alone or integrated commercial service
- Placing a burden on GitHub's servers that is disproportionate to the benefit provided to users
  (e.g., using it as a CDN, as part of a serverless application, or **hosting a production application**)
- **Any other activity unrelated to the development or testing of the software project
  associated with the repository where Codespaces was started**

Violating these terms can result in GitHub restricting or suspending access to
Codespaces, or disabling the repository in question.

**Honest assessment**: the way this project is used (as a general-purpose desktop,
playing around in Roblox Studio, etc.) can fall under "activity unrelated to software
development/testing" above — it's a gray-area use case outside the intended purpose.
If you try this, please understand that and proceed **at your own risk**. In
particular, the following usage patterns carry a higher risk of being treated as a
violation, and should be avoided:

- Running it continuously as a substitute for a everyday-use PC
- Exposing the screen/audio streaming ports publicly and providing it as a service to others
- Hosting production applications, websites, or game servers on it

If you have questions, we recommend contacting [GitHub Support](https://support.github.com/) directly.

### How this relates to similar projects

The general concept of "running a browser-only desktop on Codespaces" already has
prior art if you look for it (combinations of `noVNC` + a lightweight window manager,
for example). What this project pushes further:

- A full-featured KDE Plasma desktop via KasmVNC, instead of a lightweight WM
- A homegrown system-audio HTTP streaming setup (Selkies' standard WebRTC audio
  doesn't work under Codespaces' port restrictions)
- Running Windows apps (Roblox Studio) via Wine, including wiring up the login
  handoff between the browser and the app (a `roblox-studio-auth` protocol handler)
- A persistence mechanism so desktop settings, the Wine environment, and browser
  login state all survive a container rebuild

---

## Background (for first-timers)

This guide uses the following terms frequently. Skip this section if you already know them.

- **GitHub Codespaces**: A cloud development environment from GitHub. It's meant for
  writing code, but under the hood it's a Linux container (think: a small, disposable
  virtual machine), so with some effort you can run a whole desktop environment in it.
  Personal accounts get a free monthly quota (120 core-hours as of 2026)
- **Container / Rebuild**: A Codespace is, under the hood, a "container" — a
  lightweight virtual environment. Running "Rebuild Container" discards that container
  and rebuilds it from scratch according to the config files. **This is the single
  most important thing to understand about this project** (see "⚠️ Before you
  rebuild" below)
- **devcontainer.json**: The config file Codespaces reads when building the
  container. It specifies things like which base image to use and what to run on startup
- **KasmVNC**: Technology that displays a remote Linux desktop in a plain browser tab,
  with no dedicated client app needed. This project uses it to display the Codespaces
  desktop in a browser tab
- **Wine**: A compatibility layer that lets you run Windows applications on Linux. It
  doesn't run Windows itself — instead, it re-implements the Windows functionality
  that Windows apps call into, on the Linux side

---

## ⚠️ Before you rebuild: forgetting to save really does lose data

This actually happened. We rebuilt the container while a Roblox Studio map had
unsaved changes, and some of the data got corrupted, requiring Studio's own
auto-recovery to kick in (thankfully nothing serious was lost, but that's not
guaranteed).

**"Rebuild Container" does not ask running apps to save and exit gracefully.** It
terminates the container outright and rebuilds it, so any file that was mid-write at
that moment can simply be lost or corrupted.

Before rebuilding, always:

1. **Explicitly save inside any open app** (Roblox Studio, etc. — Ctrl+S)
2. If possible, **publish/upload to the cloud** (for Roblox, the "Publish" feature.
   Once data is on the cloud it lives outside the container and is completely
   unaffected by a rebuild)
3. **Close the app normally** — via the window's `×` button, not a force-kill.
   `kill -9` or a forced task termination can interrupt an in-progress save
4. In a terminal (Konsole or the VS Code terminal), flush pending disk writes and
   wait a moment:

```bash
sync
```

5. If you're still not confident, wait ~10 seconds after `sync` before rebuilding

The "persistence" mechanism described below keeps desktop settings and the Wine
environment itself from disappearing, but **it does not protect data you were
actively editing inside an app at that moment**. It's important to keep that
distinction in mind.

---

## What works

- Full access to a full-featured KDE Plasma desktop using **3 browser tabs**
  (Codespaces management page, screen streaming, audio streaming)
- Japanese UI and Japanese input (fcitx5 + Mozc)
- System audio playback in the browser (HTTP streaming, tens of seconds of latency)
- Windows apps via Wine (verified working with Roblox Studio)
- Desktop appearance and login state survive a container rebuild

## What doesn't work / constraints

- **No GPU**, so all 3D rendering is done in software (`llvmpipe`). Heavy 3D apps run
  at slideshow-level speed
- Codespaces port forwarding is HTTP(S) only. Real-time WebRTC audio/video doesn't
  work out of the box
- Once you exhaust the free tier, you can't use it anymore that month (resets the
  following month)
- **Note that the free tier is measured in "core-hours."** GitHub's personal-account
  free tier is 120 core-hours/month, but on the 4-core machine this project uses
  (`standardLinux32gb`), that's only **30 real hours per month** (120 ÷ 4 cores = 30
  hours). If you assume "I get 120 hours," you'll hit the limit much sooner than
  expected.

---

## Technical overview

### Base

- Boots a KDE Plasma desktop container image provided by the Selkies project, via
  Codespaces' `devcontainer.json`
- Screen streaming uses KasmVNC (a browser-native VNC implementation bundled with
  that image). The Selkies project's own WebRTC streaming (Selkies-GStreamer) doesn't
  work for this purpose, since Codespaces port forwarding is HTTP(S)-only and doesn't
  pass raw UDP/TCP

### Screen and audio

- **Screen**: KasmVNC (WebSocket-based). Setting the port forward to Public gives
  direct browser access
- **Audio**: Selkies' standard WebRTC audio doesn't work on Codespaces either, so
  we built our own setup that encodes PulseAudio's output to mp3 with `ffmpeg` and
  serves it as a plain HTTP stream. Measured stereo at 64kbps gives noticeably lower
  perceived latency than mono/lower bitrate

### Japanese localization

- `LANG`/`LC_ALL`/`LANGUAGE` are set directly as container startup environment
  variables (`containerEnv`). Editing config files after the fact gets overwritten by
  the container's startup process, so this is the reliable approach
- Japanese input uses `fcitx5` + `Mozc`

### Persistence (the most important part)

Codespaces' "Rebuild Container" wipes everything outside the repository's files
(home directory, installed apps, any open app state, etc.) and starts fresh. To work
around this, anything we don't want to lose is symlinked into a location that lives
under the repository itself.

What's persisted:
- Desktop wallpaper, icons, theme settings
- Desktop shortcuts and app launcher registrations
- The entire Wine install (`WINEPREFIX`)
- Firefox's profile (including browser login sessions/cookies)

Thanks to this, rebuilding the container leaves Japanese input settings, the Wine
environment, and browser login state intact.

---

## Things we got stuck on, and how we fixed them

### 1. `apt install` silently fails for no obvious reason

In this container environment, `fakeroot`'s default mode (SysV semaphores) isn't
supported, and `apt-get install` can fail with an internal error. The error message
isn't clear, and it makes `postCreateCommand` (run automatically when the container
is created) look like it's just hanging for no reason. This was the single trickiest
thing to figure out.

Fix (put this at the top of the setup script, permanently):

```bash
sudo update-alternatives --set fakeroot /usr/bin/fakeroot-tcp
```

### 2. `devcontainer.json` breaks and puts you into "recovery mode"

Since `devcontainer.json` is JSON, cramming a long shell command into it as a single
line is prone to escaping mistakes that break the JSON itself. When that happens, the
Codespace can't start properly and drops into recovery mode.

Fix: avoid writing setup logic directly inside `devcontainer.json` as much as
possible. Put it in a separate shell script file instead, and have
`devcontainer.json` just call that script.

### 3. Apps disappear every time you rebuild

Anything installed via `apt install`, or app settings under the home directory,
disappears completely on rebuild if it lives anywhere outside `/workspaces` (inside
the repo). We got confused more than once by "I installed this, why is it gone?"
before realizing why.

The fix is the persistence setup described above. On top of that, for anything
installed via `apt`, adding self-healing code to the service-start script ("if it's
missing, reinstall it") saves you from having to manually reinstall after every
rebuild.

### 4. 3D rendering with no GPU

With no GPU, OpenGL rendering falls back to `llvmpipe`, a software rasterizer. It
uses every CPU core to emulate rendering, and is, unsurprisingly, much slower than a
GPU.

Things that help with perceived speed:
- Lower the screen resolution (rendered pixel count directly drives the load)
- Lower graphics quality settings inside the app (shadows, anti-aliasing, etc.)
- Explicitly set `LP_NUM_THREADS` to match your core count, so the software
  rasterizer uses all available cores

> 💡 If you're paying for a higher-tier machine type (8, 16 cores, etc.), scale
> `LP_NUM_THREADS` up to match. This project assumes the free tier's 4-core machine
> and sets `LP_NUM_THREADS=4`; if you add more cores without changing this value, the
> extra cores go unused.

### 5. Switching Japanese input over VNC

In a remote desktop setup, keyboard shortcuts (like Ctrl+Space) can get intercepted
by the browser or the local OS before they ever reach the remote side. Using `xev` to
check whether a keypress is actually arriving on the remote side is a useful way to
narrow down where the problem is.

### 6. If a Wine app feels "slow," suspect a runaway process before blaming rendering

Software rendering with no GPU is inherently slow, but if something feels
*unreasonably* slow or choppy, the culprit might not be rendering at all —
**something else could be pegging the CPU**.

What actually happened to us: an editor extension's `rg` (ripgrep, used for file
search) was trying to index the huge number of files under the Wine environment
(`WINEPREFIX`) and getting stuck pegging the CPU. `top` showed a single process
sitting above 100% CPU usage.

How to spot it:

```bash
top -bn1 | head -15
```

If an unfamiliar process (especially `rg`) is pinned at the top of CPU usage, try
killing it and see if the load average drops.

```bash
kill <PID>
```

To prevent recurrence, exclude the `WINEPREFIX` directory from your editor's search
and file-watcher scope (see `.vscode/settings.json` in this repo).

### 7. Checklist for when audio streaming (ffmpeg) goes silent

Steps to narrow down the problem when there's no audio in the browser, or the audio
page is blank/erroring.

**1. First, check whether the streaming port is actually up**

```bash
ss -tln | grep 8998
```

If nothing shows up, the streaming process itself never started.

**2. Check the log**

```bash
cat /tmp/audio-stream.log
```

Check whether `ffmpeg` itself crashed with an error, or whether it's just not caught
up yet right after startup (it can briefly show as "failed" right after boot).

**3. Restart all services at once**

`start-services.sh` in this repo (also runnable from the "Restart Services" desktop
icon) includes self-healing code that reinstalls `ffmpeg` automatically if it's
missing, so trying this first is usually the fastest fix.

```bash
bash /workspaces/<repo-name>/start-services.sh
```

**4. If the screen (KasmVNC) is also flaky, suspect a startup timing lag**

If screen streaming (port 8080) intermittently returns 502, or Konsole won't open,
you may be hitting it before the container has fully finished booting. Checking the
`postStartCommand` health-check log shows where in the boot sequence things are
stuck.

```bash
cat ~/vpc-healthcheck.log
```

Waiting a few minutes and trying again usually fixes it.

---

## Software used and licenses

This project is built by combining the following open-source software. Copyright and
licensing for each belongs to its respective project.

| Component | Purpose | License |
|---|---|---|
| [Selkies](https://github.com/selkies-project) (docker-selkies-*-desktop) | Base desktop container image | Mozilla Public License 2.0 |
| [KasmVNC](https://github.com/kasmtech/KasmVNC) | Browser-native screen streaming | GPL-2.0 (TigerVNC lineage) |
| KDE Plasma | Desktop environment | GPL / LGPL (standard for the KDE project) |
| [Wine](https://www.winehq.org/) | Windows app compatibility layer | LGPL-2.1 |
| [FFmpeg](https://ffmpeg.org/) | Audio encoding/streaming | GPL (Ubuntu's standard build has `--enable-gpl` on; can be LGPL depending on build config) |
| [fcitx5](https://fcitx-im.org/wiki/Fcitx_5) | Japanese input framework | LGPL-2.1 |
| [Mozc](https://github.com/google/mozc) | Japanese input engine | BSD-3-Clause-ish |
| Ubuntu | Base OS | Varies per package (mostly GPL-family) |

> **A note on Roblox Studio**: Roblox Studio is proprietary software owned by Roblox
> Corporation, under its own license — it is not open source. This guide shares the
> experimental finding that Roblox Studio can be made to run via Wine; please review
> Roblox's Terms of Use yourself and use it at your own risk. As for the Roblox
> Player (the gameplay client, which ships with the Hyperion anti-cheat), we tested
> it in this project's environment and confirmed it detects and blocks the Wine
> environment, preventing it from launching (this is our own hands-on finding, not an
> official statement from Roblox).

---

## License (for this guide itself)

The written content of this repository (README and other documentation) is
published under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

- **Attribution (BY)**: You must credit the original author
- **NonCommercial (NC)**: Commercial use is not permitted
- **ShareAlike (SA)**: Adaptations must be published under the same license

Where code/config files (scripts, etc.) are included, they're separately licensed
under the [MIT License](https://opensource.org/licenses/MIT) instead (Creative
Commons licenses are not recommended for code).

---

## Aside (unrelated to the main content)

The author of this project is pretty lazy. To cut down on manual work, an AI
assistant (Claude) was used quite heavily throughout — checking config file
contents, narrowing down troubleshooting steps, and drafting this guide itself all
happened through back-and-forth with the AI.

There's no interest in pretending "I figured all of this out entirely on my own," so
this is stated plainly. That said, actually getting it to work still required plenty
of tedious, hands-on verification while looking at screenshots and typing things out
manually (copy-paste didn't work in a lot of places) — that part of the tedium was
very real.
