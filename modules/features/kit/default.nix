{ inputs, ... }:
{
  flake.nixosModules.m1n1x = ./_package/m1n1x-system.nix;

  flake.nixosConfigurations.j713 =
    let
      packages = inputs.self.packages.aarch64-linux;
    in
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs.m1n1xPackages = {
        inherit (packages)
          graviton
          linuxKernel
          mesa
          ;
        m1n1xBoot = packages.m1n1x-boot;
        m1n1xReport = packages.m1n1x-report;
      };

      modules = [
        ./_package/m1n1x-system.nix
        (
          { pkgs, ... }:
          {
            nixpkgs.hostPlatform = "aarch64-linux";

            hardware.m1n1x = {
              enable = true;
              board = "j713";
              wifiRegion = "US";
            };

            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
            nixpkgs.flake = {
              setFlakeRegistry = false;
              setNixPath = false;
            };

            networking.hostName = "m4-air";
            networking.networkmanager = {
              enable = true;
              wifi.backend = "iwd";
            };
            boot.kernel.sysctl = {
              "net.ipv4.conf.all.arp_ignore" = 1;
              "net.ipv4.conf.all.arp_announce" = 2;
            };

            hardware.bluetooth.enable = true;
            hardware.graphics.enable = true;

            services.displayManager.sddm.enable = true;
            services.desktopManager.plasma6 = {
              enable = true;
              enableQt5Integration = false;
            };
            # Apple firmware updates are managed by macOS, not fwupd.
            services.fwupd.enable = false;
            # The graphical profile enables Orca and speech synthesis by
            # default; defer their large speech backend/voice closure until
            # explicitly requested.
            services.orca.enable = false;
            services.speechd.enable = false;
            programs.kde-pim.enable = false;
            environment.plasma6.excludePackages = with pkgs.kdePackages; [
              elisa
              gwenview
              khelpcenter
              krdp
              okular
              plasma-browser-integration
              plasma-keyboard
              plasma-workspace-wallpapers
              qtvirtualkeyboard
              union
            ];
            documentation.enable = false;

            services.pulseaudio.enable = false;
            security.rtkit.enable = true;
            services.pipewire = {
              enable = true;
              alsa.enable = true;
              pulse.enable = true;
            };

            users.users.m4 = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "networkmanager"
              ];
              initialPassword = "change-me";
            };

            system.stateVersion = "26.05";
          }
        )
      ];
    };

  flake.nixosConfigurations.j773g = inputs.self.nixosConfigurations.j713.extendModules {
    modules = [
      (
        { lib, ... }:
        {
          hardware.m1n1x.board = lib.mkForce "j773g";
          networking.hostName = lib.mkForce "m4-mini";
        }
      )
    ];
  };

  perSystem =
    { ... }:
    let
      # The kit and its root system are always built by the ARM Linux builder.
      buildPkgs = import inputs.nixpkgs {
        localSystem = "aarch64-linux";
      };

      nixos = inputs.self.nixosConfigurations.j713;
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
        inherit nixos;
      };

      packages.m1n1x-kit-j773g = makeKit {
        nixos = inputs.self.nixosConfigurations.j773g;
        suffix = "-j773g";
      };
    };
}
