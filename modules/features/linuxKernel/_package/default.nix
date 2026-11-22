{
  lib,
  fetchFromGitHub,
  linuxKernel,
  llvmPackages_21,
  buildPackages,
  # Needs /var/cache/ccache in nix.settings.extra-sandbox-paths.
  useCcache ? false,
  extraKernelPatches ? [ ],
  randstructSeed ? "",
  features ? { },
}:
(linuxKernel.manualConfig {
  inherit randstructSeed features;
  configfile = ./shared.config;

  version = "7.3.0";
  # Must match CONFIG_LOCALVERSION.
  modDirVersion = "7.3.0-m1n1x";

  # Latest Gravity integration/apple-silicon-7.3-20261119-526 snapshot.
  src = fetchFromGitHub {
    owner = "GravityLinux";
    repo = "linux";
    rev = "c7e7b86aed0c4c052851e5c3b2c02088c0602f02";
    hash = "sha256-c+fOJqeqqwiHs9Cdz0RVZ/nReLgh0VEF3iEbGuq6o4E=";
  };

  # Shared T8132 support and board-local J713/J773G enablement.
  kernelPatches =
    map (name: {
      inherit name;
      patch = ./patches + "/${name}";
    }) (lib.attrNames (builtins.readDir ./patches))
    ++ extraKernelPatches;

  allowImportFromDerivation = true;

  stdenv = llvmPackages_21.stdenv;
  extraMakeFlags = [
    "LLVM=1"
    # From 7.3, LLVM=1 links host tools with lld; nixpkgs' host compiler is GCC.
    "HOSTLDFLAGS=-fuse-ld=bfd"
  ]
  # Overrides the unwrapped clang the kernel build sets.
  ++ lib.optional useCcache "CC=${lib.getExe buildPackages.ccache} ${lib.getExe llvmPackages_21.stdenv.cc.cc}";

  extraMeta.platforms = [ "aarch64-linux" ];
}).overrideAttrs
  (
    old:
    {
      # m1n1 boots Image.gz.
      buildFlags = map (flag: if flag == "Image" then "Image.gz" else flag) old.buildFlags;
      # Keep modules_install and dtbs_install from nixpkgs; only switch the
      # image install target to match the compressed Image.gz build.
      installTargets = map (target: if target == "install" then "zinstall" else target) old.installTargets;
    }
    // lib.optionalAttrs useCcache {
      # Structured attributes export only env.
      env = (old.env or { }) // {
        CCACHE_DIR = "/var/cache/ccache";
        CCACHE_UMASK = "007";
        CCACHE_SLOPPINESS = "include_file_mtime,include_file_ctime,time_macros";
      };
    }
  )
