{ self, ... }:
{
  flake.nixosModules.m1n1xSystem =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.m1n1x ];

      nixpkgs.hostPlatform = "aarch64-linux";
      hardware.m1n1x = {
        enable = true;
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
      # Defer the graphical profile's large speech backend until requested.
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
    };
}
