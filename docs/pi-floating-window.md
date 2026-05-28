# Pi floating terminal and attached overlay surfaces

This fork adds a small primitive for Pi-style workflows: create a real cmux/Ghostty
terminal window from the CLI/socket, place it explicitly, optionally keep it
floating, and optionally seed it with a command.

The point is to avoid rendering a terminal inside Pi's text UI. Pi, a Pi
extension, or a shell skill can instead ask cmux to open a normal native terminal
window that sits beside or over the agent window and remains scriptable through
the cmux socket.

## CLI

```bash
cmux new-window \
  --floating \
  --frame 747,-917,1000,700 \
  --name "Pi task shell" \
  --command 'printf "ready\n"; pwd'
```

Useful flags:

- `--frame x,y,width,height`: initial native AppKit window frame.
- `--position x,y --size width,height`: equivalent split form.
- `--floating`: keep the new window above normal windows.
- `--focus true|false`: activate the new window. Defaults to `true`.
- `--no-focus`: create it without stealing focus.
- `--cwd path`: set the initial terminal working directory.
- `--command text`: type the command into the terminal and press Enter.
- `--name title`: set the initial workspace/window title.

macOS/AppKit window coordinates are bottom-left based. If an external display is
arranged below the main display, its `y` values are negative. For example, a
side display with visible frame `(565, -982, 1512, 950)` can use a frame such as
`747,-917,1000,700`.

## Socket API

The CLI maps onto `window.create`:

```bash
cmux rpc window.create '{
  "floating": true,
  "frame": "747,-917,1000,700",
  "title": "Pi task shell",
  "initial_input": "printf \"ready\\n\"; pwd\r",
  "focus": true
}'
```

The response includes a `window_ref`. Use the standard cmux API to inspect and
control it:

```bash
cmux rpc system.identify '{}'
cmux rpc surface.list '{"window_id":"window:3","workspace_id":"workspace:3"}'
cmux rpc surface.read_text '{"window_id":"window:3","workspace_id":"workspace:3","surface_id":"surface:3","lines":80}'
cmux send --workspace workspace:3 --surface surface:3 'echo still alive\n'
cmux close-window --window window:3
```

## Pi integration shape

For Pi, keep the integration thin:

1. Pi asks cmux to create a floating terminal with a known title and frame.
2. Pi stores the returned `window_ref`, `workspace_ref`, and `surface_ref`.
3. Pi sends commands with `surface.send_text` or `cmux send`.
4. Pi reads state with `surface.read_text` when it needs to poll.
5. The user can still interact with the native terminal directly.

That gives the user a real shell at any time while keeping enough structured
state for Pi or an agent to steer it.

## Attached overlay surfaces

For the `pi-hazn-shell` workflow, the preferred primitive is an attached overlay
surface rather than a separate native floating window. It is still a real cmux
terminal or browser, but it is drawn over the active pane and belongs to that
cmux workspace. It does not mutate the split tree.

```bash
cmux rpc pane.create '{
  "workspace_id": "workspace:1",
  "type": "terminal",
  "placement": "overlay",
  "initial_command": "zsh -lic '\''jjui; exec zsh -l'\''",
  "focus": true
}'

cmux rpc pane.create '{
  "workspace_id": "workspace:1",
  "type": "browser",
  "placement": "overlay",
  "url": "https://example.com",
  "focus": true
}'
```

The overlay has a 2 px black border. Browser overlays use the regular cmux
browser panel, including the always-visible address bar; their border is also
mirrored in the browser portal layer so WebKit content cannot cover it.

The Pi bridge can steer the overlay with standard socket methods:

```bash
cmux rpc surface.read_text '{"workspace_id":"workspace:1","surface_id":"surface:2","lines":80}'
cmux rpc browser.snapshot '{"workspace_id":"workspace:1","surface_id":"surface:2","compact":true}'
cmux rpc surface.send_text '{"workspace_id":"workspace:1","surface_id":"surface:2","text":"echo hi\n"}'
cmux rpc surface.background '{"workspace_id":"workspace:1","surface_id":"surface:2"}'
cmux rpc surface.focus '{"workspace_id":"workspace:1","surface_id":"surface:2"}'
cmux rpc surface.close '{"workspace_id":"workspace:1","surface_id":"surface:2"}'
```

For the haznfloat dev setup, launch cmux from anywhere with:

```bash
cmux-haznfloat
```

That command opens the tagged debug app with `CMUX_SOCKET_MODE=full`,
`CMUX_SOCKET_PATH=/tmp/cmux-debug-haznfloat.sock`, and waits for the socket.
Use `cmux-haznfloat --rebuild` when the app bundle needs to be rebuilt, and
`cmux-haznfloat --smoke` to run the Pi overlay controls smoke test after launch.

cmux also publishes Pi-specific events when the user triggers the overlay
shortcuts on an overlay created with `pi_hazn_shell_controls: true`. Ordinary
cmux terminals and ordinary cmux overlays keep their normal Ctrl key behavior:

| Shortcut | Event | Effect |
| --- | --- | --- |
| `Ctrl+T` | `pi_hazn_shell.transfer_requested` | Pi reads the terminal/browser state and transfers it to the agent; the overlay stays open. |
| `Ctrl+B` | `pi_hazn_shell.backgrounded` | cmux hides the overlay and keeps the process/browser alive. Pi handles this silently without triggering an agent turn. |
| `Ctrl+Q` | Menu choice dependent | cmux opens the local Pi session menu. Transfer/background/kill choices publish the same Pi events as the direct shortcuts; cancel publishes nothing. |
| `Cmd+W` | Menu choice dependent | When a Pi-controlled overlay is focused, cmux opens the same menu as `Ctrl+Q` without closing the window. |

Pi subscribes with:

```bash
cmux events \
  --name pi_hazn_shell.transfer_requested \
  --name pi_hazn_shell.backgrounded \
  --name pi_hazn_shell.closed \
  --no-ack --no-heartbeats --reconnect
```

For live verification against a running debug cmux, use the smoke harness:

```bash
CMUX_SOCKET_PATH=/tmp/cmux-debug-haznfloat.sock ./scripts/smoke-pi-overlay-controls.py
```

It uses cmux itself as the test probe: create overlay surfaces, read terminal
screen text with `surface.read_text`, simulate `Ctrl+T`, inspect the event
stream, and confirm normal overlays do not publish Pi shortcut events.
