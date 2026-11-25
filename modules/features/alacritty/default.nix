{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.alacritty = inputs.wrappers.wrappers.alacritty.wrap {
      inherit pkgs;
      settings = {
        general.import = [ "${./theme.toml}" ];
        window = {
          dynamic_padding = true;
          decorations = "None";
        };
        window.padding = {
          x = 10;
          y = 10;
        };
        font = {
          size = 14;
          # TODO: package font
          normal.family = "JetBrains Mono Nerd Font";
        };
      };
    };
  };
}
