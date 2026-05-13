#!/usr/bin/env python3
import json
import os
import select
import shutil
import subprocess
import sys
import time


EVENT_TRANSFER = "pi_hazn_shell.transfer_requested"
EVENT_BACKGROUND = "pi_hazn_shell.backgrounded"


def die(message):
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def cmux_cli():
    configured = os.environ.get("CMUX_CLI")
    if configured:
        return configured
    if os.path.exists("/tmp/cmux-cli"):
        return "/tmp/cmux-cli"
    found = shutil.which("cmux")
    if found:
        return found
    die("cmux CLI not found. Set CMUX_CLI or launch the tagged dev app so /tmp/cmux-cli exists.")


def cmux_env():
    env = os.environ.copy()
    socket_path = env.get("CMUX_SOCKET_PATH") or "/tmp/cmux-debug-haznfloat.sock"
    env["CMUX_SOCKET_PATH"] = socket_path
    return env


CLI = cmux_cli()
ENV = cmux_env()


def run_rpc(method, params, timeout=10):
    cmd = [CLI, "rpc", method, json.dumps(params)]
    proc = subprocess.run(cmd, env=ENV, text=True, capture_output=True, timeout=timeout)
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or f"{cmd!r} failed"
        die(detail)
    try:
        return json.loads(proc.stdout or "{}")
    except json.JSONDecodeError as error:
        die(f"{method} returned invalid JSON: {error}: {proc.stdout!r}")


def read_line_timeout(stream, timeout):
    ready, _, _ = select.select([stream], [], [], timeout)
    if not ready:
        return None
    return stream.readline()


def stop_process(proc):
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=1)


def latest_event_seq(event_name):
    proc = subprocess.Popen(
        [CLI, "events", "--name", event_name, "--no-heartbeat"],
        env=ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        line = read_line_timeout(proc.stdout, 3)
        if not line:
            stderr = proc.stderr.read().strip() if proc.stderr else ""
            die(f"timed out waiting for event-stream ack{': ' + stderr if stderr else ''}")
        frame = json.loads(line)
        if frame.get("type") != "ack":
            die(f"expected event-stream ack, got {frame}")
        return int(frame["resume"]["latest_seq"])
    finally:
        stop_process(proc)


def wait_event_after(event_name, after_seq, timeout):
    proc = subprocess.Popen(
        [
            CLI,
            "events",
            "--after",
            str(after_seq),
            "--name",
            event_name,
            "--no-ack",
            "--no-heartbeat",
            "--limit",
            "1",
        ],
        env=ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        line = read_line_timeout(proc.stdout, timeout)
        if not line:
            return None
        return json.loads(line)
    finally:
        stop_process(proc)


def workspace_ref():
    payload = run_rpc("workspace.current", {})
    return payload.get("workspace_ref") or payload.get("workspace_id")


def create_overlay(workspace, marker, pi_controls):
    command = f"zsh -lc 'printf \"{marker}\\n\"; sleep 300'"
    return run_rpc(
        "pane.create",
        {
            "workspace_id": workspace,
            "type": "terminal",
            "placement": "overlay",
            "focus": True,
            "pi_hazn_shell_controls": pi_controls,
            "initial_command": command,
        },
    )


def close_surface(workspace, surface):
    try:
        run_rpc("surface.close", {"workspace_id": workspace, "surface_id": surface}, timeout=5)
    except SystemExit:
        raise
    except Exception:
        pass


def surface_item(workspace, surface):
    payload = run_rpc("surface.list", {"workspace_id": workspace})
    for item in payload.get("surfaces", []):
        if item.get("id") == surface:
            return item
    return None


def visible_orphan_terminal_count():
    payload = run_rpc("debug.portal.stats", {})
    totals = payload.get("totals", {})
    return int(totals.get("visible_orphan_terminal_subview_count") or 0)


def visible_terminal_count():
    payload = run_rpc("debug.portal.stats", {})
    totals = payload.get("totals", {})
    return int(totals.get("visible_terminal_subview_count") or 0)


def wait_visible_terminal_count_at_most(limit, timeout=3):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = visible_terminal_count()
        if last <= limit:
            return last
        time.sleep(0.1)
    die(f"visible terminal portal count stayed above {limit}; last count was {last}")


def wait_visible_terminal_count_at_least(limit, timeout=3):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = visible_terminal_count()
        if last >= limit:
            return last
        time.sleep(0.1)
    die(f"visible terminal portal count stayed below {limit}; last count was {last}")


def read_text(workspace, surface):
    payload = run_rpc("surface.read_text", {"workspace_id": workspace, "surface_id": surface, "lines": 40})
    return payload.get("text") or ""


def wait_for_marker(workspace, surface, marker, timeout=8):
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        last = read_text(workspace, surface)
        if marker in last:
            return last
        time.sleep(0.2)
    die(f"surface {surface} never rendered {marker!r}; last screen text was:\n{last}")


def expect(condition, message):
    if not condition:
        die(message)


def main():
    socket_path = ENV.get("CMUX_SOCKET_PATH")
    print(f"cmux_cli={CLI}")
    print(f"cmux_socket={socket_path}")

    workspace = workspace_ref()
    expect(workspace, "no current cmux workspace")
    print(f"workspace={workspace}")
    baseline_visible_terminals = visible_terminal_count()
    print(f"baseline_visible_terminals={baseline_visible_terminals}")

    pi_surface = None
    normal_surface = None
    try:
        pi = create_overlay(workspace, "PI_SMOKE_READY", True)
        pi_surface = pi["surface_id"]
        expect(pi.get("pi_hazn_shell_controls") is True, "Pi overlay did not echo pi_hazn_shell_controls=true")
        wait_for_marker(workspace, pi_surface, "PI_SMOKE_READY")
        wait_visible_terminal_count_at_least(baseline_visible_terminals + 1)
        print(f"pi_overlay={pi_surface} screen_state=ok")

        before = latest_event_seq(EVENT_TRANSFER)
        run_rpc("debug.shortcut.simulate", {"combo": "ctrl+t"})
        event = wait_event_after(EVENT_TRANSFER, before, 3)
        expect(event is not None, "Ctrl+T on Pi overlay did not publish transfer event")
        expect(event.get("surface_id") == pi_surface, f"transfer event was for {event.get('surface_id')}, not {pi_surface}")
        print(f"pi_ctrl_t_event_seq={event.get('seq')}")

        before = latest_event_seq(EVENT_BACKGROUND)
        run_rpc("debug.shortcut.simulate", {"combo": "ctrl+b"})
        event = wait_event_after(EVENT_BACKGROUND, before, 3)
        expect(event is not None, "Ctrl+B on Pi overlay did not publish background event")
        expect(event.get("surface_id") == pi_surface, f"background event was for {event.get('surface_id')}, not {pi_surface}")
        backgrounded = surface_item(workspace, pi_surface)
        expect(backgrounded is not None, "backgrounded Pi overlay disappeared instead of staying pollable")
        expect(backgrounded.get("visible") is False, f"backgrounded Pi overlay still listed as visible: {backgrounded}")
        expect(backgrounded.get("focused") is False, f"backgrounded Pi overlay still listed as focused: {backgrounded}")
        after_background_visible_terminals = wait_visible_terminal_count_at_most(baseline_visible_terminals)
        expect(visible_orphan_terminal_count() == 0, "Ctrl+B left a visible orphan terminal portal behind")
        print(
            f"pi_ctrl_b_event_seq={event.get('seq')} visible=false "
            f"visible_terminals={after_background_visible_terminals} portal_orphans=0"
        )

        close_surface(workspace, pi_surface)
        pi_surface = None

        normal = create_overlay(workspace, "NORMAL_SMOKE_READY", False)
        normal_surface = normal["surface_id"]
        expect(normal.get("pi_hazn_shell_controls") is False, "normal overlay unexpectedly has Pi controls")
        wait_for_marker(workspace, normal_surface, "NORMAL_SMOKE_READY")
        print(f"normal_overlay={normal_surface} screen_state=ok")

        before = latest_event_seq(EVENT_TRANSFER)
        run_rpc("debug.shortcut.simulate", {"combo": "ctrl+t"})
        event = wait_event_after(EVENT_TRANSFER, before, 1.25)
        expect(event is None, f"normal overlay unexpectedly published Pi transfer event: {event}")
        print("normal_ctrl_t_event=none")
    finally:
        if normal_surface:
            close_surface(workspace, normal_surface)
        if pi_surface:
            close_surface(workspace, pi_surface)

    print("smoke=ok")


if __name__ == "__main__":
    main()
