#!/usr/bin/env bash
set -euo pipefail

TAG="${CMUX_MCUX_TAG:-mcux}"
CASK_TOKEN="${CMUX_MCUX_CASK_TOKEN:-mcux}"
TAP_NAME="${CMUX_MCUX_TAP:-haznai/mcux-dev}"
APP_TARGET="${CMUX_MCUX_APP_TARGET:-mcux.app}"
CLI_TARGET="${CMUX_MCUX_CLI_TARGET:-mcux}"
DRY_RUN=0
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: scripts/homebrew-install-dev-build.sh [options]

Build this checkout in Release configuration and install that local dev build
through a generated Homebrew cask. Defaults to:
  tag:        mcux
  local tap:  haznai/mcux-dev
  cask token: mcux
  app target: /Applications/mcux.app
  cli target: mcux

Options:
  --dry-run     Generate and print the local cask without installing it
  --skip-build  Reuse the existing Release build from DerivedData
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew is required to install ${CASK_TOKEN}." >&2
  exit 1
fi

brew_no_update() {
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew "$@"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"
}

plist_set_string() {
  local plist="$1"
  local key="$2"
  local value="${3//\"/\\\"}"
  /usr/libexec/PlistBuddy -c "Set :${key} \"${value}\"" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${key} string \"${value}\"" "$plist"
}

plist_set_env() {
  local plist="$1"
  local key="$2"
  local value="${3//\"/\\\"}"
  /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :LSEnvironment:${key} \"${value}\"" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :LSEnvironment:${key} string \"${value}\"" "$plist"
}

slug="$(printf '%s' "$TAG" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
[[ -n "$slug" ]] || slug="mcux"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$HOME/Library/Developer/Xcode/DerivedData/cmux-${slug}-release"
release_app_path="${derived_data}/Build/Products/Release/cmux.app"
socket_path="/tmp/cmux-${slug}.sock"
debug_log_path="/tmp/cmux-${slug}.log"
app_support_dir="$HOME/Library/Application Support/cmux"
cmuxd_socket="${app_support_dir}/cmuxd-${slug}.sock"
bundle_id="com.cmuxterm.app.${slug}"
work_dir="${TMPDIR:-/tmp}/cmux-homebrew-${CASK_TOKEN}"
payload_dir="${work_dir}/payload"
payload_app="${payload_dir}/${APP_TARGET}"
zip_path="${work_dir}/${CASK_TOKEN}.zip"
cask_path="${work_dir}/${CASK_TOKEN}.rb"

marketing_version="$(awk -F= '/MARKETING_VERSION = / { gsub(/[ ;]/, "", $2); print $2; exit }' "$repo_dir/GhosttyTabs.xcodeproj/project.pbxproj")"
[[ -n "$marketing_version" ]] || marketing_version="0.0.0"
revision="local"
if command -v jj >/dev/null 2>&1 && [[ -d "$repo_dir/.jj" ]]; then
  revision="$(cd "$repo_dir" && jj log --no-graph -r 'latest(::@ & ~empty())' --no-pager --template 'commit_id.short()' 2>/dev/null || printf local)"
fi
version="${marketing_version}-dev-${revision}"

build_release_direct() {
  cd "$repo_dir"
  ./scripts/ensure-ghosttykit.sh
  xcodebuild \
    -project GhosttyTabs.xcodeproj \
    -scheme cmux \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build
  if [[ -d "$repo_dir/cmuxd" ]]; then
    (cd "$repo_dir/cmuxd" && zig build -Doptimize=ReleaseFast)
  fi
}

build_release() {
  if command -v zig >/dev/null 2>&1 && [[ "$(zig version 2>/dev/null || true)" == "0.15.2" ]]; then
    build_release_direct
    return
  fi

  if command -v devenv >/dev/null 2>&1; then
    (
      cd "$repo_dir"
      CMUX_MCUX_DERIVED_DATA="$derived_data" devenv shell bash -lc '
        set -euo pipefail
        ./scripts/ensure-ghosttykit.sh
        xcodebuild \
          -project GhosttyTabs.xcodeproj \
          -scheme cmux \
          -configuration Release \
          -destination "platform=macOS" \
          -derivedDataPath "$CMUX_MCUX_DERIVED_DATA" \
          ONLY_ACTIVE_ARCH=YES \
          CODE_SIGNING_ALLOWED=NO \
          build
        if [[ -d cmuxd ]]; then
          (cd cmuxd && zig build -Doptimize=ReleaseFast)
        fi
      '
    )
    return
  fi

  build_release_direct
}

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  build_release
fi

if [[ ! -d "$release_app_path" ]]; then
  echo "error: expected Release app not found: $release_app_path" >&2
  echo "hint: run without --skip-build, or check the xcodebuild output." >&2
  exit 1
fi

rm -rf "$work_dir"
mkdir -p "$payload_dir"
ditto "$release_app_path" "$payload_app"

plist="$payload_app/Contents/Info.plist"
plist_set_string "$plist" CFBundleName "mcux"
plist_set_string "$plist" CFBundleDisplayName "mcux"
plist_set_string "$plist" CFBundleIdentifier "$bundle_id"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$plist" >/dev/null 2>&1 || true
plist_set_env "$plist" CMUX_TAG "$slug"
plist_set_env "$plist" CMUX_SOCKET_PATH "$socket_path"
plist_set_env "$plist" CMUXD_UNIX_PATH "$cmuxd_socket"
plist_set_env "$plist" CMUX_SOCKET_ENABLE "1"
plist_set_env "$plist" CMUX_SOCKET_MODE "allowAll"
plist_set_env "$plist" CMUX_ALLOW_SOCKET_OVERRIDE "1"
plist_set_env "$plist" CMUX_DEBUG_LOG "$debug_log_path"
plist_set_env "$plist" CMUX_REMOTE_DAEMON_ALLOW_LOCAL_BUILD "1"
plist_set_env "$plist" CMUXTERM_REPO_ROOT "$repo_dir"

if [[ -x "$repo_dir/cmuxd/zig-out/bin/cmuxd" ]]; then
  mkdir -p "$payload_app/Contents/Resources/bin"
  cp "$repo_dir/cmuxd/zig-out/bin/cmuxd" "$payload_app/Contents/Resources/bin/cmuxd"
  chmod +x "$payload_app/Contents/Resources/bin/cmuxd"
fi

mkdir -p "$payload_app/Contents/Resources/bin"
cat > "$payload_app/Contents/Resources/bin/$CLI_TARGET" <<EOF
#!/usr/bin/env bash
set -euo pipefail
script_dir="\$(cd "\$(dirname "\$0")" && pwd)"
export CMUX_SOCKET_PATH=$(shell_quote "$socket_path")
export CMUXD_UNIX_PATH=$(shell_quote "$cmuxd_socket")
exec "\$script_dir/cmux" "\$@"
EOF
chmod +x "$payload_app/Contents/Resources/bin/$CLI_TARGET"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$payload_app" || true
fi
/usr/bin/codesign --force --deep --sign - --timestamp=none "$payload_app" >/dev/null

(
  cd "$payload_dir"
  ditto -c -k --sequesterRsrc --keepParent "$APP_TARGET" "$zip_path"
)
sha256="$(shasum -a 256 "$zip_path" | cut -d' ' -f1)"
file_url="$(python3 - "$zip_path" <<'PY'
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).resolve().as_uri())
PY
)"

cat > "$cask_path" <<EOF
cask "${CASK_TOKEN}" do
  version "${version}"
  sha256 "${sha256}"

  url "${file_url}"
  name "mcux"
  desc "Release-configuration local dev build of cmux from this checkout"
  homepage "https://github.com/haznai/cmux-hazn"

  depends_on macos: ">= :sonoma"

  app "${APP_TARGET}"
  binary "#{appdir}/${APP_TARGET}/Contents/Resources/bin/${CLI_TARGET}", target: "${CLI_TARGET}"

  uninstall quit: "${bundle_id}"

  zap trash: [
    "~/Library/Preferences/${bundle_id}.plist",
  ]
end
EOF

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Generated local cask: $cask_path"
  echo "Payload: $zip_path"
  echo
  cat "$cask_path"
  exit 0
fi

/usr/bin/osascript -e "tell application id \"${bundle_id}\" to quit" >/dev/null 2>&1 || true
pkill -f "/Applications/${APP_TARGET}/Contents/MacOS/cmux" >/dev/null 2>&1 || true
sleep 0.3

tap_dir="$(brew_no_update --repo "$TAP_NAME" 2>/dev/null || true)"
if [[ -z "$tap_dir" || ! -d "$tap_dir" ]]; then
  tap_owner="${TAP_NAME%%/*}"
  tap_repo="${TAP_NAME#*/}"
  if [[ -z "$tap_owner" || -z "$tap_repo" || "$tap_owner" == "$tap_repo" ]]; then
    echo "error: CMUX_MCUX_TAP must look like owner/name, got: $TAP_NAME" >&2
    exit 1
  fi
  tap_dir="$(brew_no_update --repository)/Library/Taps/${tap_owner}/homebrew-${tap_repo}"
  mkdir -p "$tap_dir"
  if [[ ! -f "$tap_dir/README.md" ]]; then
    printf '# %s\n\nLocal tap generated by cmux scripts/homebrew-install-dev-build.sh.\n' "$TAP_NAME" > "$tap_dir/README.md"
  fi
fi
mkdir -p "$tap_dir/Casks"
cp "$cask_path" "$tap_dir/Casks/${CASK_TOKEN}.rb"

if brew_no_update list --cask "$CASK_TOKEN" >/dev/null 2>&1; then
  brew_no_update uninstall --cask --force "$CASK_TOKEN"
fi

if [[ -d "/Applications/${APP_TARGET}" ]]; then
  rm -rf "/Applications/${APP_TARGET}"
fi

brew_no_update install --cask --force "$CASK_TOKEN"

if [[ -d "/Applications/${APP_TARGET}" ]]; then
  xattr -dr com.apple.quarantine "/Applications/${APP_TARGET}" 2>/dev/null || true
  xattr -cr "/Applications/${APP_TARGET}" 2>/dev/null || true
  /usr/bin/codesign --force --deep --sign - --timestamp=none "/Applications/${APP_TARGET}" >/dev/null
fi

echo
echo "Installed this checkout's Release dev build through Homebrew:"
echo "  app: /Applications/${APP_TARGET}"
echo "  cli: ${CLI_TARGET}"
echo "  socket: ${socket_path}"
echo
echo "Launch with: open /Applications/${APP_TARGET}"
