{ moduleWithSystem, inputs, ... }:
{
  flake.nixosModules.hyprland = moduleWithSystem (
    { self', pkgs, ... }:
    {
      programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        package = self'.packages.hyprland;
        portalPackage = pkgs.xdg-desktop-portal-hyprland;
      };

      services.displayManager = {
        defaultSession = "hyprland";
        autoLogin = {
          enable = true;
          user = "dilshad";
        };
        sddm = {
          enable = true;
          wayland.enable = true;
        };
      };
    }
  );

  perSystem =
    {
      self',
      pkgs,
      lib,
      ...
    }:
    {
      packages.hyprland = inputs.wrappers.wrappers.hyprland.wrap {
        inherit pkgs;
        "hyprland.lua".path = "${./.}/hyprland.lua";
        env = {
          "HYPRLAND_PROGRAM_ALACRITTY" = lib.getExe self'.packages.alacritty;
          "HYPRLAND_PROGRAM_HYPRPAPER" = lib.getExe self'.packages.hyprpaper;
          "HYPRLAND_PROGRAM_HYPRLOCK" = lib.getExe pkgs.hyprlock;
          "HYPRLAND_PROGRAM_HYPRSHUTDOWN" = lib.getExe pkgs.hyprshutdown;
          "HYPRLAND_PROGRAM_HYPRPICKER" = lib.getExe pkgs.hyprpicker;
          "HYPRLAND_PROGRAM_QUICKSHELL" = lib.getExe self'.packages.quickshell;
          "HYPRLAND_PROGRAM_DUNST" = lib.getExe pkgs.dunst;
        };
      };
    };
}
