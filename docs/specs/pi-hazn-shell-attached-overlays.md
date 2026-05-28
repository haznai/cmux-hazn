# Pi Hazn Shell Attached Overlays

Status: active local spec
Last updated: 2026-05-26

## Why This Exists

The user wants to live in one large terminal workspace without losing the ability to launch helper terminals, browser panes, Hunk, agents, and one-off tools while Pi keeps running. The original Pi xterm overlay solved the control model, but it could not match native terminal performance and rendering fidelity for heavy TUI apps. cmux already owns real terminal and browser surfaces, so the better design is to let cmux render the surface and let Pi own the lifecycle contract.

The core product bet is simple: cmux changes the render surface, not the Pi session model. A cmux-backed shell should still feel like a Pi shell session: launch, transfer, background, attach, poll, kill.

## Invariants

- A user can launch an attached terminal or browser overlay from Pi without blocking the agent's own work.
- The overlay is attached to the active cmux workspace/pane, not a random detached native window.
- The overlay has a visible 2 px black boundary. Browser overlays mirror that boundary in the browser portal layer because WebKit content is hosted above the SwiftUI panel tree.
- Terminal overlays are real terminal surfaces, so heavy TUIs like jjui and Neovim should render through cmux/Ghostty rather than Pi's xterm text renderer.
- Browser overlays are real browser surfaces, keep a visible URL/control strip, and are driven through native cmux `browser.*` RPCs rather than terminal input.
- `Ctrl+T` transfers current state to Pi without killing or backgrounding the session.
- `Ctrl+B` backgrounds the session visually and logically. The process/browser stays alive and pollable. This is a local lifecycle action; it must not message the agent or trigger a turn.
- Open cmux sessions appear in the same Pi session widget and `/attach`/`/kill` choices as normal shell sessions.
- `Ctrl+Q` opens the local Pi session menu. `Cmd+W` has the same menu behavior when the Pi-controlled overlay is focused, while normal cmux windows keep their regular close-window behavior otherwise. The menu can transfer, background, kill, or cancel; only the kill choice closes the overlay session, and none of the close/menu paths should trigger a new agent turn.
- `/attach <id>` brings a cmux overlay back or focuses an already-open cmux overlay.
- `/kill <id>` closes a cmux-backed session the same way it closes a normal Pi overlay session.
- Private user shell sessions must stay private to the user. The agent should not see or poll them unless the user chose an agent-visible mode.
- Normal cmux terminals must not lose their ordinary Ctrl key behavior. Pi overlay shortcuts are scoped to Pi-launched, Pi-controlled overlays.

## User Workflows

Start the tagged cmux dev app:

```bash
cd "/Users/hazn/Desktop/new.code/cmux-hazn"
just open
```

Run the local diagnostics:

```bash
just doctor
just debug-socket
just debug-log 120
just debug-smoke
```

Rebuild and smoke the tagged app:

```bash
just rebuild-open
just smoke-open
```

Launch from Pi after restarting Pi with the local `pi-hazn-shell` package installed:

```text
/shell:interactive --cmux "zsh -lic \"jjui; exec zsh -l\""
/shell:interactive --cmux --browser "https://example.com"
```

Use private user mode when the agent should not see the session:

```text
/shell:user --cmux "zsh -lic \"jjui; exec zsh -l\""
```

## Architecture

`pi-hazn-shell` is the Pi package that owns slash commands, agent-callable tools, dispatch and hands-free semantics, and the session lifecycle registry. cmux owns native terminal/browser rendering and the attached overlay geometry.

The bridge has two directions:

- Pi to cmux: open terminal/browser overlay, read terminal text or browser snapshots, send terminal input, drive browser actions through native cmux `browser.*` RPCs, background, focus, close.
- cmux to Pi: emit Pi-specific overlay events for transfer/background/close when a Pi-controlled overlay receives `Ctrl+T`, `Ctrl+B`, or a `Ctrl+Q`/overlay-owned `Cmd+W` menu choice.

The cmux surface is tagged as Pi-controlled when launched through the Pi cmux backend. Only tagged surfaces intercept Pi overlay shortcuts. Ordinary cmux surfaces keep their normal key handling.

The background path is intentionally redundant. cmux handles `Ctrl+B` locally, emits the event, and Pi also calls `surface.background` when it receives the background event. That protects against stale UI/model races where the event reaches Pi but the visual overlay fails to hide. This redundancy must remain operationally local and silent: no `sendMessage`, no transcript dump, no agent wake-up. `Ctrl+T` is the explicit boundary crossing.

## Current Repository Shape

cmux fork checkout:

```text
/Users/hazn/Desktop/new.code/cmux-hazn
```

Pi package checkout:

```text
/Users/hazn/Desktop/new.code/pi-hazn-shell
```

The cmux writable remote is:

```text
https://github.com/haznai/cmux-hazn.git
```

The upstream `manaflow-ai/cmux` remote should not be used for this local progress branch. This checkout is meant to push the current cmux experiment to the writable fork.

## Verification Policy

Fast local checks for this work:

```bash
just --list
just doctor
just debug-socket
just debug-smoke
```

For app rebuilds:

```bash
just smoke-open
```

For Pi package checks:

```bash
cd "/Users/hazn/Desktop/new.code/pi-hazn-shell"
just doctor
just doctor-cmux
just test
```

When Swift builds need local dependency relief, the established debug path is `CMUX_SKIP_ZIG_BUILD=1`. Do not claim a full release-quality build from that shortcut, it is for local feature verification.

## Open Follow-Ups

- Re-run manual focus testing after any change touching `Workspace`, `WorkspaceContentView`, `TerminalWindowPortal`, or `GhosttyTerminalView`.
- Keep the smoke harness honest by checking actual visible portal state, not only RPC model state.
- Keep Pi package installation local during this work. A stale GitHub package cache already caused confusion once.
- If this becomes permanent, decide whether `main` in `haznai/cmux-hazn` is the long-lived experiment branch or whether the work should be split into smaller PR-ready branches later.
