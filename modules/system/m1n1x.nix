{ self, ... }:
{
  flake.nixosModules.m1n1xSystem =
    { pkgs, ... }:
    {
      imports = [
        self.nixosModules.m1n1x
        self.nixosModules.hyprland
      ];

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
      boot.kernel.sysctl = {
        "net.ipv4.conf.all.arp_ignore" = 1;
        "net.ipv4.conf.all.arp_announce" = 2;
      };

      hardware.bluetooth.enable = true;
      hardware.graphics.enable = true;

      # Apple firmware updates are managed by macOS, not fwupd.
      services.fwupd.enable = false;
      documentation.enable = false;

      services.pulseaudio.enable = false;
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
      };

      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-gnome3;
      };

      system.stateVersion = "26.05";
    };
}
