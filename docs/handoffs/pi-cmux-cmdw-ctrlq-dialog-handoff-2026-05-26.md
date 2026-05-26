# Pi/cmux Cmd+W and Ctrl+Q dialog handoff

Date: 2026-05-26
Repos:

- cmux: `/Users/hazn/Desktop/new.code/cmux-hazn`
- Pi package: `/Users/hazn/Desktop/new.code/pi-hazn-shell`

## Latest user correction

The latest correction overrides the previous interpretation:

- `Cmd+W` should be **exactly like `Ctrl+Q`** for a Pi-launched cmux overlay.
- It should use the **same dialog/menu as always**.
- It should not silently close the cmux overlay.
- It should not kill the shell unless the user chooses the kill option in that dialog.
- `Ctrl+T` remains the only explicit transfer-to-agent shortcut.
- `Ctrl+B` should background silently, no agent message, no transcript dump, no new turn.

The current working copy still has the wrong final behavior for `Cmd+W`/`Ctrl+Q`: cmux maps them to a direct close. Treat that as unfinished.

## Current working-copy state

### cmux repo modified files

```text
Sources/AppDelegate.swift
cmuxTests/AppDelegateShortcutRoutingTests.swift
docs/pi-floating-window.md
docs/specs/pi-hazn-shell-attached-overlays.md
justfile
docs/handoffs/pi-cmux-cmdw-ctrlq-dialog-handoff-2026-05-26.md
```

Current cmux behavior in the working copy:

- `Ctrl+T` on Pi-controlled cmux overlay publishes `pi_hazn_shell.transfer_requested`.
- `Ctrl+B` backgrounds locally and publishes `pi_hazn_shell.backgrounded` for Pi to keep lifecycle state in sync.
- `Ctrl+Q` currently calls `workspace.closeAttachedOverlaySurface(..., force: true)` directly.
- `Cmd+W` was added to the same direct close path as `Ctrl+Q`.
- That direct close path is now wrong per latest user correction, because user wants the normal dialog/menu.

Relevant cmux code:

- `Sources/AppDelegate.swift`, around `PiHaznOverlayShortcutAction` and `handlePiHaznOverlayShortcut`.
- `Sources/Workspace.swift`, `backgroundAttachedOverlaySurface` and `closeAttachedOverlaySurface`.
- Test currently codifying the wrong direct-close behavior:
  - `cmuxTests/AppDelegateShortcutRoutingTests.swift`, `testCmdWClosesFocusedPiHaznAttachedOverlayWithoutClosingCmuxWindow`.
  - Replace this with a dialog/menu behavior test.

### pi-hazn-shell repo modified files

```text
README.md
docs/user-shell-commands.md
index.ts
skills/pi-hazn-shell/SKILL.md
tests/spawn-command.test.ts
```

Current Pi package behavior in the working copy:

- `Ctrl+B` background events are silent. No `pi.sendMessage`, no `triggerTurn`.
- Removed the earlier background notification path, keeping the model simple.
- `Ctrl+T` still transfers output to the agent.
- cmux active sessions still remain locally attachable/killable.

Relevant Pi code:

- `index.ts`, `registerCmuxActive`, especially handling of `pi_hazn_shell.backgrounded`.
- `overlay-component.ts` and `reattach-overlay.ts` are the source of truth for the normal Pi `Ctrl+Q` dialog/menu behavior. Read these before implementing the cmux equivalent.

## Target product invariant

cmux is only the renderer. Pi owns the session lifecycle model.

Shortcut behavior for a Pi-controlled cmux overlay should be:

| Shortcut | Desired behavior |
| --- | --- |
| `Ctrl+T` | Transfer current state to the agent. Keep overlay open. |
| `Ctrl+B` | Background/hide overlay. Keep process/browser alive. Silent. |
| `Ctrl+Q` | Open the same dialog/menu users already know from Pi overlays. |
| `Cmd+W` | Same as `Ctrl+Q`, because it is close-window muscle memory. |

The dialog/menu should offer the same choices as normal Pi overlay UX, roughly:

- Transfer, when agent-visible.
- Background.
- Kill process.
- Cancel.

For private/user-only sessions, preserve private behavior: no transfer to agent, no agent-visible lifecycle message.

## Suggested implementation direction

Keep it simple. Do **not** add policy flags or clever branching.

1. In cmux, make both `Ctrl+Q` and overlay-owned `Cmd+W` route to a dialog/menu state, not direct close.
2. The cmux dialog should mirror Pi overlay choices and defaults as closely as possible.
3. When the user chooses:
   - Transfer: publish `pi_hazn_shell.transfer_requested`, keep overlay visible.
   - Background: call local `workspace.backgroundAttachedOverlaySurface`, publish `pi_hazn_shell.backgrounded`, no Pi agent wake-up.
   - Kill: call local close surface, publish `pi_hazn_shell.closed`.
   - Cancel: dismiss dialog, no event.
4. Keep ordinary cmux terminals untouched. Only `piHaznShellControls == true` overlays should intercept these shortcuts.
5. Update docs so they say `Ctrl+Q`/`Cmd+W` open the dialog, not silently close.
6. Update/remove the current direct-close Cmd+W test.

Question to resolve while implementing: where should the dialog render?

- Best simple path is probably a small cmux-native overlay/menu attached to the Pi-controlled overlay.
- Do not wake the Pi agent just to ask for a menu. The user wants this to feel local.
- Use Pi's existing dialog behavior as the UX spec, not necessarily its implementation.

## Tutorial: how to get back to the work

### 1. Open cmux repo

```bash
cd "/Users/hazn/Desktop/new.code/cmux-hazn"
jj status --no-pager
```

Use `jj`, never raw `git`.

### 2. Make sure cmux dev app/socket is running

Fast path if the app is already built:

```bash
just open
```

If rebuilding is needed, this machine currently needs Apple toolchain paths and no Zig build:

```bash
env \
  PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin" \
  LD=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang \
  CMUX_SKIP_ZIG_BUILD=1 \
  just rebuild-open
```

The expected socket is:

```text
/tmp/cmux-debug-haznfloat.sock
```

Check it:

```bash
just doctor
just debug-socket
```

If `just doctor` says the socket is missing, run `just open` again.

### 3. Restart Pi before testing Pi package changes

Pi does not reload package code in already-running sessions. Restart Pi after editing `/Users/hazn/Desktop/new.code/pi-hazn-shell`.

The Pi package should be the local checkout, not the GitHub cache:

```text
/Users/hazn/Desktop/new.code/pi-hazn-shell
```

### 4. Launch a Pi-controlled cmux overlay from Pi

Use `jjui` examples, not `hunk`:

```text
/shell:interactive --cmux "zsh -lic \"jjui; exec zsh -l\""
```

For private/user-only mode:

```text
/shell:user --cmux "zsh -lic \"jjui; exec zsh -l\""
```

Browser sanity check:

```text
/shell:interactive --cmux --browser "https://example.com"
```

### 5. Manual behavior test checklist

With the cmux overlay focused:

1. Press `Ctrl+T`.
   - Expected: Pi receives transferred terminal/browser state.
   - Overlay stays open.
2. Press `Ctrl+B`.
   - Expected: overlay hides/backgrounds.
   - No agent message, no transcript dump, no new turn.
   - `/attach` should list/focus it.
   - `/kill` should list/kill it.
3. Press `Ctrl+Q`.
   - Desired next behavior: show the normal menu/dialog.
   - Current working-copy behavior: direct close, wrong.
4. Press `Cmd+W`.
   - Desired next behavior: exactly same as `Ctrl+Q`, show normal menu/dialog.
   - Current working-copy behavior: direct close, wrong.

### 6. Automated checks

Pi package full suite:

```bash
cd "/Users/hazn/Desktop/new.code/pi-hazn-shell"
just test
```

Last result before this handoff:

```text
27 files passed, 120 tests passed
```

cmux smoke test for current transfer/background behavior:

```bash
cd "/Users/hazn/Desktop/new.code/cmux-hazn"
just debug-smoke
```

Last result before this handoff:

```text
smoke=ok
```

cmux targeted XCTest command, using Apple toolchain env:

```bash
cd "/Users/hazn/Desktop/new.code/cmux-hazn"
env \
  PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin" \
  LD=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang \
  CMUX_SKIP_ZIG_BUILD=1 \
  just test-unit -only-testing:cmuxTests/AppDelegateShortcutRoutingTests/testCmdWClosesFocusedPiHaznAttachedOverlayWithoutClosingCmuxWindow test
```

Last result before this handoff:

```text
Executed 1 test, 0 failures
```

But that test currently validates the now-wrong direct close behavior. Replace it when implementing the dialog/menu.

## Testing gotchas

- Plain `just test-unit ...` may fail because Nix `clang`/`ld` get picked up and Xcode builds break with errors like `unknown argument: -index-store-path` or `Unknown options: -Xlinker ...`.
- Use the Apple toolchain `PATH` and `LD=.../clang` shown above.
- `zig` is missing on this machine. Use `CMUX_SKIP_ZIG_BUILD=1` for local debug builds.
- If cmux socket is missing, restart the dev app with `just open` or `just rebuild-open`.
- Restart Pi after every `pi-hazn-shell` package change.

## Remote / repo policy

- cmux writable remote is `haznai https://github.com/haznai/cmux-hazn.git`.
- The upstream `origin` was intentionally removed.
- Use `jj` for all VCS operations.
- Push cmux progress to remote `main` only when ready.
- Use the local `pi-hazn-shell` package checkout only.

## What was already verified

- `pi-hazn-shell`: `deno fmt --check index.ts tests/spawn-command.test.ts README.md docs/user-shell-commands.md skills/pi-hazn-shell/SKILL.md` passed.
- `pi-hazn-shell`: `just test` passed, 120 tests.
- `cmux`: `just debug-smoke` passed with `smoke=ok`.
- `cmux`: targeted Cmd+W direct-close test passed, but that test now needs replacement because user clarified the desired behavior.

## Next best move

Start in cmux:

```bash
cd "/Users/hazn/Desktop/new.code/cmux-hazn"
```

Then:

1. Read `Sources/AppDelegate.swift` around `handlePiHaznOverlayShortcut`.
2. Read Pi dialog behavior in `/Users/hazn/Desktop/new.code/pi-hazn-shell/overlay-component.ts` and `reattach-overlay.ts`.
3. Implement a cmux-native Pi overlay menu for `Ctrl+Q` and overlay-owned `Cmd+W`.
4. Keep `Ctrl+B` silent.
5. Update tests/docs.
6. Run Pi tests and cmux targeted/smoke checks.
