set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  @just --list

# Open the tagged haznfloat dev app with the Pi/cmux socket setup.
open:
  @./scripts/cmux-haznfloat

# Rebuild, then open the tagged haznfloat dev app.
rebuild-open:
  @./scripts/cmux-haznfloat --rebuild

# Rebuild, open, then run the Pi overlay control smoke test.
smoke-open:
  @./scripts/cmux-haznfloat --rebuild --smoke

# Print the short workflow for continuing Pi/cmux overlay work.
work:
  @printf '%s\n' \
    'cd "/Users/hazn/Desktop/new.code/cmux-hazn"' \
    'just open' \
    'just doctor' \
    'just debug-socket' \
    'just debug-log 120' \
    'just debug-smoke' \
    'just rebuild-open' \
    'just smoke-open' \
    '' \
    'Pi launch examples:' \
    '/shell:interactive --cmux "zsh -lic \"jjui; exec zsh -l\""' \
    '/shell:interactive --cmux --browser "https://example.com"'

# Show the current Pi/cmux overlay spec.
spec:
  @sed -n '1,260p' docs/specs/pi-hazn-shell-attached-overlays.md

# Show the consolidated Codex handoff for this work.
handoff:
  @sed -n '1,260p' docs/handoffs/codex-019dfbc0-c1e5-78d1-984b-49d43e98984d-consolidated-handoff.md

# Print a local health report for the tagged dev app, sockets, logs, and tools.
doctor:
  #!/usr/bin/env bash
  set -euo pipefail
  tag="${CMUX_TAG:-haznfloat}"
  slug="$(printf '%s' "$tag" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  [[ -n "$slug" ]] || slug="haznfloat"
  app="$HOME/Library/Developer/Xcode/DerivedData/cmux-${slug}/Build/Products/Debug/cmux DEV ${slug}.app"
  sock="/tmp/cmux-debug-${slug}.sock"
  log="/tmp/cmux-debug-${slug}.log"
  echo "cmux doctor"
  echo "repo: $PWD"
  echo "tag: $tag"
  echo "slug: $slug"
  echo
  echo "tools:"
  for tool in just xcodebuild swift python3 node npm clang; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  ok      %s -> %s\n' "$tool" "$(command -v "$tool")"
    else
      printf '  missing %s\n' "$tool"
    fi
  done
  if command -v zig >/dev/null 2>&1; then
    printf '  ok      zig -> %s\n' "$(command -v zig)"
  else
    echo "  optional zig missing (use CMUX_SKIP_ZIG_BUILD=1 for local debug builds)"
  fi
  echo
  echo "paths:"
  [[ -d "$app" ]] && echo "  ok      app: $app" || echo "  missing app: $app"
  [[ -S "$sock" ]] && echo "  ok      socket: $sock" || echo "  missing socket: $sock"
  [[ -f "$log" ]] && echo "  ok      log: $log" || echo "  missing log: $log"
  for file in /tmp/cmux-last-cli-path /tmp/cmux-last-socket-path /tmp/cmux-last-debug-log-path; do
    if [[ -r "$file" ]]; then
      echo "  $(basename "$file"): $(cat "$file")"
    else
      echo "  $(basename "$file"): missing"
    fi
  done
  echo
  echo "processes:"
  pgrep -fl "cmux DEV ${slug}.app/Contents/MacOS/cmux DEV" || true
  echo
  echo "socket users:"
  if [[ -S "$sock" ]]; then
    lsof -nU 2>/dev/null | grep -F "$sock" || echo "  socket exists, no lsof owner found"
  else
    echo "  no socket at $sock"
  fi
  echo
  if command -v jj >/dev/null 2>&1 && [[ -d .jj ]]; then
    jj status --no-pager
  else
    echo "jj workspace missing; initialize with: jj git init --colocate"
  fi

# Alias for muscle memory while debugging.
debug: doctor

# Show recent cmux debug log lines from the last launched tagged app.
debug-log lines="120":
  @log="$(cat /tmp/cmux-last-debug-log-path 2>/dev/null || echo /tmp/cmux-debug-haznfloat.log)"; \
  echo "log: $log"; \
  if [[ -f "$log" ]]; then tail -n {{lines}} "$log"; else echo "missing log: $log" >&2; exit 1; fi

# Follow the current cmux debug log.
tail-log:
  @log="$(cat /tmp/cmux-last-debug-log-path 2>/dev/null || echo /tmp/cmux-debug-haznfloat.log)"; \
  echo "tailing: $log"; \
  touch "$log"; \
  tail -f "$log"

# Inspect the current tagged cmux socket and the process holding it.
debug-socket:
  @sock="$(cat /tmp/cmux-last-socket-path 2>/dev/null || echo /tmp/cmux-debug-haznfloat.sock)"; \
  echo "socket: $sock"; \
  if [[ -S "$sock" ]]; then ls -l "$sock"; lsof -nU 2>/dev/null | grep -F "$sock" || true; else echo "missing socket: $sock" >&2; exit 1; fi

# Run the Pi overlay smoke test against the last launched tagged socket.
debug-smoke:
  @sock="$(cat /tmp/cmux-last-socket-path 2>/dev/null || echo /tmp/cmux-debug-haznfloat.sock)"; \
  echo "CMUX_SOCKET_PATH=$sock"; \
  CMUX_SOCKET_PATH="$sock" ./scripts/smoke-pi-overlay-controls.py

# Stop and remove local files for the tagged dev app. Defaults to haznfloat.
debug-clean tag="haznfloat":
  @slug="$(printf '%s' "{{tag}}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"; \
  [[ -n "$slug" ]] || slug="haznfloat"; \
  echo "cleaning cmux tag: $slug"; \
  pkill -f "cmux DEV ${slug}.app/Contents/MacOS/cmux DEV" || true; \
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData/cmux-${slug}" "/tmp/cmux-${slug}"; \
  rm -f "/tmp/cmux-debug-${slug}.sock" "/tmp/cmux-debug-${slug}.log" "$HOME/Library/Application Support/cmux/cmuxd-dev-${slug}.sock"

# Run any file in scripts/ by basename, selecting the interpreter by extension.
script name *args:
  @script="scripts/{{name}}"; \
  if [[ ! -f "$script" ]]; then script="scripts/{{name}}.sh"; fi; \
  if [[ ! -f "$script" ]]; then echo "script not found: {{name}}" >&2; exit 1; fi; \
  case "$script" in \
    *.py) exec python3 "$script" {{args}} ;; \
    *.js) exec node "$script" {{args}} ;; \
    *.swift) exec swift "$script" {{args}} ;; \
    *.m) mkdir -p /tmp/cmux-just; clang -framework Foundation -framework CoreGraphics -o /tmp/cmux-just/"$(basename "$script" .m)" "$script"; exec /tmp/cmux-just/"$(basename "$script" .m)" {{args}} ;; \
    *) exec "$script" {{args}} ;; \
  esac

bench-window-visibility *args:
  @swift scripts/bench-window-visibility.swift {{args}}

build-ghostty-cli-helper *args:
  @./scripts/build-ghostty-cli-helper.sh {{args}}

build-sign-upload *args:
  @./scripts/build-sign-upload.sh {{args}}

build-remote-daemon-release-assets *args:
  @./scripts/build_remote_daemon_release_assets.sh {{args}}

bump-version *args:
  @./scripts/bump-version.sh {{args}}

circleci-auto-approve *args:
  @python3 scripts/circleci_auto_approve.py {{args}}

cmux-haznfloat *args:
  @./scripts/cmux-haznfloat {{args}}

create-virtual-display *args:
  @mkdir -p /tmp/cmux-just
  @clang -framework Foundation -framework CoreGraphics -o /tmp/cmux-just/create-virtual-display scripts/create-virtual-display.m
  @/tmp/cmux-just/create-virtual-display {{args}}

derive-sparkle-public-key *args:
  @swift scripts/derive_sparkle_public_key.swift {{args}}

download-prebuilt-ghosttykit *args:
  @./scripts/download-prebuilt-ghosttykit.sh {{args}}

download-with-retry *args:
  @./scripts/download-with-retry.sh {{args}}

ensure-ghosttykit *args:
  @./scripts/ensure-ghosttykit.sh {{args}}

frame-probe-tui *args:
  @python3 scripts/frame-probe-tui.py {{args}}

generate-dark-icon *args:
  @python3 scripts/generate_dark_icon.py {{args}}

generate-nightly-icon *args:
  @python3 scripts/generate_nightly_icon.py {{args}}

install-zig-ci *args:
  @./scripts/install-zig-ci.sh {{args}}

kitty-image-demo *args:
  @./scripts/kitty-image-demo.sh {{args}}

launch-tagged-automation *args:
  @./scripts/launch-tagged-automation.sh {{args}}

lint-auxiliary-window-close-shortcuts *args:
  @python3 scripts/lint_auxiliary_window_close_shortcuts.py {{args}}

notify-probe *args:
  @./scripts/notify_probe.sh {{args}}

perf-activation-session *args:
  @python3 scripts/perf-activation-session.py {{args}}

probe-pure-prompt-duplication *args:
  @python3 scripts/probe-pure-prompt-duplication.py {{args}}

prune-nightly-release-assets *args:
  @python3 scripts/prune_nightly_release_assets.py {{args}}

release-pretag-guard *args:
  @./scripts/release-pretag-guard.sh {{args}}

release-asset-guard *args:
  @node scripts/release_asset_guard.js {{args}}

release-asset-guard-test *args:
  @node scripts/release_asset_guard.test.js {{args}}

reload *args:
  @./scripts/reload.sh {{args}}

reload2 *args:
  @./scripts/reload2.sh {{args}}

reloadp *args:
  @./scripts/reloadp.sh {{args}}

reloads *args:
  @./scripts/reloads.sh {{args}}

run-e2e *args:
  @./scripts/run-e2e.sh {{args}}

run-tests-v1 *args:
  @./scripts/run-tests-v1.sh {{args}}

run-tests-v2 *args:
  @./scripts/run-tests-v2.sh {{args}}

setup *args:
  @./scripts/setup.sh {{args}}

sign-cmux-bundle *args:
  @./scripts/sign-cmux-bundle.sh {{args}}

smoke-pi-overlay-controls *args:
  @python3 scripts/smoke-pi-overlay-controls.py {{args}}

smoke-test-ci *args:
  @./scripts/smoke-test-ci.sh {{args}}

sparkle-generate-appcast *args:
  @./scripts/sparkle_generate_appcast.sh {{args}}

sparkle-generate-keys *args:
  @./scripts/sparkle_generate_keys.sh {{args}}

swift-file-length-budget *args:
  @python3 scripts/swift_file_length_budget.py {{args}}

swift-warning-budget *args:
  @python3 scripts/swift_warning_budget.py {{args}}

test-unit *args:
  @./scripts/test-unit.sh {{args}}

validate-xcframework-archive *args:
  @python3 scripts/validate-xcframework-archive.py {{args}}

verify-main-thread-ca-transactions *args:
  @./scripts/verify-main-thread-ca-transactions.sh {{args}}
