{
  lib,
  m1n1,
  nixos-icons,
  fetchFromGitHub,
  rustPlatform,
  stage ? 2,
}:
assert lib.elem stage [
  1
  2
];
(m1n1.override {
  customLogo = "${nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake-white.png";
}).overrideAttrs
  (
    finalAttrs: old: {
      version = "1.6.1-unstable-2026-11-19";

      src = fetchFromGitHub {
        owner = "GravityLinux";
        repo = "bootloader";
        rev = "ac17c97fc15c91fcdfd6009f5788f808558fe26f";
        fetchSubmodules = true;
        hash = "sha256-P+cl1Z8lI4VA3sDDAyzP1twtygUfHqsh9VEbkuE0ugI=";
      };

      cargoDeps = rustPlatform.fetchCargoVendor {
        inherit (finalAttrs) pname version;
        src = "${finalAttrs.src}/rust";
        sourceRoot = "rust";
        hash = "sha256-/2JQ31pMHbNjZsIu2RLCWzNul/qzL1O2+XB3qdOEb2U=";
      };

      patches = lib.filesystem.listFilesRecursive (./patches + "/stage${toString stage}");

      makeFlags = [
        "ARCH=${m1n1.stdenv.cc.targetPrefix}"
        "RELEASE=1"
        "CHAINLOADING=${if stage == 1 then "1" else "0"}"
        "LOGO=custom"
        # No DCP support for the M4 yet.
        "NO_DISPLAY=1"
      ];

      installPhase = ''
        runHook preInstall
        install -Dm644 build/m1n1.bin -t $out/lib/m1n1/
        install -Dm644 LICENSE.* 3rdparty_licenses/LICENSE.* -t $out/share/doc/m1n1/licenses/
        runHook postInstall
      '';

      env = (old.env or { }) // {
        M1N1_VERSION_TAG = "m1n1x-ac17c97-stage${toString stage}";
      };
    }
  )
