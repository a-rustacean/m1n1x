{ inputs, ... }:
let
  defaultPackages = inputs.self.packages.aarch64-linux;

  m1n1xModule =
    { lib, ... }:
    {
      imports = [ ./_nixos.nix ];

      hardware.m1n1x.packages = {
        graviton = lib.mkDefault defaultPackages.graviton;
        linuxKernel = lib.mkDefault defaultPackages.linuxKernel;
        mesa = lib.mkDefault defaultPackages.mesa;
        m1n1xBoot = lib.mkDefault defaultPackages.m1n1x-boot;
        m1n1xReport = lib.mkDefault defaultPackages.m1n1x-report;
      };
    };
in
{
  # The hardware module is reusable by host flakes. Its package options have
  # defaults from this flake, but each can be overridden by the importing host.
  flake.nixosModules.default = m1n1xModule;
  flake.nixosModules.m1n1x = m1n1xModule;

  perSystem =
    { ... }:
    let
      # The kit and its root system are always built by the ARM Linux builder.
      buildPkgs = import inputs.nixpkgs {
        localSystem = "aarch64-linux";
      };

      packages = inputs.self.packages.aarch64-linux;

      makeKit =
        {
          nixos,
          suffix ? "",
        }:
        let
          cfg = nixos.config.hardware.m1n1x;
          toplevel = nixos.config.system.build.toplevel;
          makeExt4Fs = args: buildPkgs.callPackage "${nixos.pkgs.path}/nixos/lib/make-ext4-fs.nix" args;
        in
        buildPkgs.callPackage ./_package {
          inherit makeExt4Fs toplevel;
          systemLabel = "${nixos.config.system.nixos.label}${suffix}";
          board = cfg.board;
          rootUuid = cfg.image.rootUuid;
          volumeLabel = cfg.image.label;
          installer = packages.m1n1x-installer;
          installerSource = packages.m1n1x-installer-source;
          m1n1xBoot = packages.m1n1x-boot;
          guide = ./_package/GUIDE.md;
        };
    in
    {
      packages.m1n1x-kit = makeKit {
        nixos = inputs.self.nixosConfigurations.j713;
      };

      packages.m1n1x-kit-j773g = makeKit {
        nixos = inputs.self.nixosConfigurations.j773g;
        suffix = "-j773g";
      };
    };
}
