{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.hyprpaper = inputs.wrappers.lib.wrapPackage {
      inherit pkgs;
      package = pkgs.hyprpaper;
      flags."--config" = pkgs.writeText "hyprpaper.conf" ''
        wallpaper {
          monitor =
          path = ${./wallpaper.jpg}
          fit_mode = cover
        }
        splash = false
      '';
    };
  };
}
