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
