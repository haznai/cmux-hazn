# Pi cmux Browser Control Plan

Status: active implementation plan
Last updated: 2026-05-26

## Critique of the First Plan

The first plan had the right product shape: a native cmux browser should keep the Pi session lifecycle instead of becoming a separate browser automation world. The weak part was the phrase "same exact thing as an interactive shell." That is correct for lifecycle, but wrong for communication. A browser is not a PTY. Treating it like one would produce a fake stdin API, ambiguous text dumps, and another pile of edge-case glue.

The browser plan needs one hard split:

- Lifecycle is identical to cmux shell sessions: launch, transfer, background, attach, poll, kill, menu, private mode.
- Interaction is browser-native: navigate, snapshot, click, fill, press, scroll, wait, and inspect through cmux `browser.*` RPCs.

The first plan also under-specified focus. Browser actions issued by Pi must not raise cmux, steal macOS focus, or change the user's active pane unless the action is explicitly `attach`/`focus`. Socket actions should mutate the browser model in place and return an observation. The user-visible overlay remains the user's surface; the agent gets controlled, non-focus-stealing access through Pi.

The plan should not build a second browser automation stack inside `pi-hazn-shell`. cmux already owns browser RPCs, element lookup, frames, page snapshots, screenshots, console/error collection, and navigation. Pi should expose a small, typed adapter over that existing control plane, then expand only when real workflows need more.

## Product Invariant

A Pi-launched cmux browser session is a Pi session whose renderer is a native cmux browser overlay. It should feel like the existing interactive shell overlay for lifecycle and collaboration, while using browser-native operations for communication.

A user or agent can launch:

```ts
pi_hazn_shell({
  command: "https://example.com",
  mode: "interactive",
  backend: "cmux",
  surfaceType: "browser"
})
```

After launch, the same session id supports:

```ts
pi_hazn_shell({ sessionId: "browser-1" })
pi_hazn_shell({ attach: "browser-1" })
pi_hazn_shell({ sessionId: "browser-1", kill: true })
```

and browser-specific actions:

```ts
pi_hazn_shell({
  sessionId: "browser-1",
  browser: { action: "navigate", url: "https://news.ycombinator.com" }
})

pi_hazn_shell({
  sessionId: "browser-1",
  browser: { action: "click", text: "new" }
})
```

## Desired User Behavior

| Operation | Expected browser-session behavior |
| --- | --- |
| Launch | Open a native cmux browser overlay attached to the active cmux workspace/pane. |
| Poll | Return title, URL, compact accessibility/page snapshot, and useful browser state. |
| Transfer (`Ctrl+T`) | Send the current browser snapshot to the agent, keep the browser open. |
| Background (`Ctrl+B`) | Hide the overlay silently, keep the browser/session alive. |
| Menu (`Ctrl+Q`, overlay-owned `Cmd+W`) | Show transfer/background/kill/cancel, exactly like shell cmux overlays. |
| Attach | Show/focus the existing browser overlay. |
| Kill | Close the browser overlay and unregister the Pi session. |
| Private mode | Keep the session invisible to the agent-facing tool; no transfer or polling. |

## Browser Action Surface

Start with the smallest useful API. Do not expose the entire cmux browser RPC surface on day one.

```ts
type BrowserSelectorHint = {
  selector?: string
  ref?: string
  text?: string
  role?: string
  name?: string
  label?: string
  placeholder?: string
  exact?: boolean
}

type CmuxBrowserAction =
  | { action: "snapshot" }
  | { action: "navigate"; url: string; timeoutMs?: number }
  | ({ action: "click" } & BrowserSelectorHint)
  | ({ action: "fill"; value: string } & BrowserSelectorHint)
  | ({ action: "type"; text?: string; value?: string } & Omit<BrowserSelectorHint, "text">)
  | { action: "press"; key: string }
  | ({ action: "scroll"; x?: number; y?: number; deltaX?: number; deltaY?: number } & BrowserSelectorHint)
  | ({ action: "wait"; timeoutMs?: number; urlContains?: string; loadState?: "loading" | "interactive" | "complete"; function?: string } & BrowserSelectorHint)
```

Every action returns a fresh observation. This is the browser equivalent of sending input to a shell and reading the terminal afterwards.

```text
Session browser-1 (running, cmux browser)
Title: Example Domain
URL: https://example.com/
Snapshot:
...
```

## Why These Actions First

- `snapshot` is the read path and validates the session without side effects.
- `navigate` proves browser model mutation through cmux RPC without focus stealing.
- `click`, `fill`, and `press` cover most login/search/forms workflows.
- `scroll` and `wait` make multi-step flows reliable.
- Richer actions can be added later from existing cmux RPCs when a real workflow demands them.

## Architecture

`pi-hazn-shell` remains the owner of session identity, private/public visibility, tool schema, slash commands, and agent-visible messages.

cmux remains the owner of browser rendering and browser automation. Pi calls cmux RPCs through the existing bridge.

Implementation shape:

1. Extend the Pi tool schema with a `browser` action object.
2. Reject `browser` actions unless the target active session is a cmux session with `surfaceType: "browser"`.
3. Add bridge helpers that call existing cmux RPCs:
   - `browser.snapshot`
   - `browser.navigate`
   - `browser.click`
   - `browser.fill`
   - `browser.press`
   - `browser.scroll`
   - `browser.wait`
4. After each action, call `browser.snapshot` and return the updated observation.
5. Keep lifecycle commands (`background`, `attach`, `kill`, `listBackground`) on the existing session-manager path.
6. Keep `Ctrl+T`, `Ctrl+B`, `Ctrl+Q`, and overlay-owned `Cmd+W` on the existing cmux Pi overlay shortcut path.

## Focus Policy

Browser actions from Pi must not steal macOS focus. The only commands allowed to intentionally focus/show the browser are:

- `pi_hazn_shell({ attach: id })`
- `/attach <id>`
- explicit future focus actions if they are named as focus actions

All other browser actions operate through cmux socket RPCs and preserve the user's current cmux/macOS focus context.

## Testing Plan

### cmux

Add targeted coverage for browser overlays, parallel to the shell shortcut tests:

- Pi-controlled browser overlay receives `Ctrl+T` and publishes `pi_hazn_shell.transfer_requested`.
- `Ctrl+B` backgrounds browser overlay and keeps it listed/pollable.
- `Ctrl+Q` opens the Pi menu; cancel keeps the browser overlay open.
- overlay-owned `Cmd+W` opens the same menu and does not close the cmux window.
- menu kill closes only the browser overlay and publishes `pi_hazn_shell.closed`.

Extend the smoke harness with a browser branch:

1. Create `type: "browser"`, `placement: "overlay"`, `pi_hazn_shell_controls: true`.
2. Navigate to `https://example.com` or a local deterministic page.
3. Verify `browser.snapshot` returns title/URL/page content.
4. Simulate `Ctrl+T`, verify transfer event.
5. Simulate `Ctrl+B`, verify hidden but still listed.
6. Verify ordinary non-Pi browser overlays do not emit Pi shortcut events.

### pi-hazn-shell

Add tests for:

- Tool schema accepts `browser` action object.
- Browser actions reject non-cmux sessions.
- Browser actions reject cmux terminal sessions.
- `navigate` calls `browser.navigate`, then `browser.snapshot`.
- `click`/`fill` route to browser RPC helpers and return updated snapshot.
- `Ctrl+T` transfer for browser sessions includes browser snapshot, not terminal read text.
- `Ctrl+B` remains silent.
- Private `/shell:user --cmux --browser` remains invisible to agent-facing tool APIs.

## Manual Verification

Use the tagged cmux app:

```bash
cd "/Users/hazn/Desktop/new.code/cmux-hazn"
just smoke-open
```

Restart Pi so the local `pi-hazn-shell` package is loaded, then run:

```text
/shell:interactive --cmux --browser "https://example.com"
```

Manual checks:

1. `Ctrl+T` transfers browser title, URL, and snapshot to the agent.
2. `Ctrl+B` hides the browser with no agent message.
3. `/attach <id>` restores it.
4. `Ctrl+Q` opens the menu.
5. `Cmd+W` opens the same menu.
6. Kill menu choice closes only the overlay.
7. Agent-side browser actions navigate/click/fill without stealing macOS focus.

## Acceptance Criteria

The feature is done when this loop works without GUI automation:

```ts
const launch = await pi_hazn_shell({
  command: "https://example.com",
  mode: "interactive",
  backend: "cmux",
  surfaceType: "browser"
})

await pi_hazn_shell({
  sessionId: launch.sessionId,
  browser: { action: "navigate", url: "https://news.ycombinator.com" }
})

await pi_hazn_shell({
  sessionId: launch.sessionId,
  browser: { action: "click", text: "new" }
})

await pi_hazn_shell({ sessionId: launch.sessionId })
```

The user can still use the visible cmux browser directly while the agent interacts through Pi. Lifecycle parity remains intact, and browser communication stays browser-native.
