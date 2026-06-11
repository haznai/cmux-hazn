{ pkgs, ... }:

{
  stdenv = pkgs.stdenvNoCC;
  apple.sdk = null;

  packages = [
    pkgs.zig_0_15
    pkgs.gettext
  ];

  # cmux/Ghostty currently requires Zig 0.15.2. Homebrew's `zig` tracks newer
  # releases, so point the build scripts at the pinned devenv tool instead.
  env.CMUX_ZIG = "${pkgs.zig_0_15}/bin/zig";

  enterShell = ''
    # Keep Nix-provided Zig/gettext on PATH, but do not let Nix compiler wrapper
    # variables leak into Xcode. Xcode must use Apple's toolchain.
    unset CC CXX LD AR SDKROOT MACOSX_DEPLOYMENT_TARGET \
      NIX_CC NIX_CFLAGS_COMPILE NIX_LDFLAGS NIX_LDFLAGS_FOR_BUILD \
      NIX_ENFORCE_NO_NATIVE NIX_HARDENING_ENABLE NIX_BINTOOLS \
      NIX_BINTOOLS_WRAPPER_TARGET_HOST_arm64_apple_darwin \
      NIX_CC_WRAPPER_TARGET_HOST_arm64_apple_darwin \
      NIX_DONT_SET_RPATH NIX_DONT_SET_RPATH_FOR_BUILD NIX_NO_SELF_RPATH \
      NIX_IGNORE_LD_THROUGH_GCC NIX_PKG_CONFIG_WRAPPER_TARGET_HOST_arm64_apple_darwin \
      NIX_APPLE_SDK_VERSION ZERO_AR_DATE
    echo "cmux dev env: zig $(zig version), msgfmt $(command -v msgfmt)"
  '';
}
