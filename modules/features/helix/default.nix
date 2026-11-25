{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.helix = inputs.wrappers.wrappers.helix.wrap {
      inherit pkgs;
      settings = {
        theme = "catppuccin_mocha";

        editor = {
          soft-wrap.enable = true;
          auto-format = true;

          line-number = "relative";
          true-color = true;
          rulers = [
            80
            100
          ];

          cursorline = true;
          color-modes = true;

          trim-final-newlines = true;
          trim-trailing-whitespace = true;

          popup-border = "none";

          end-of-line-diagnostics = "hint";

          statusline = {
            left = [
              "mode"
              "spinner"
              "spacer"
              "spacer"
              "version-control"
            ];

            center = [
              "read-only-indicator"
              "file-base-name"
              "file-modification-indicator"
            ];

            right = [
              "diagnostics"
              "selections"
              "position"
              "file-encoding"
              "file-line-ending"
              "file-type"
            ];

            separator = "|";

            mode = {
              normal = "󰚄 NOR";
              insert = "󰚄 INS";
              select = "󰚄 SEL";
            };
          };

          lsp = {
            display-messages = true;
            display-progress-messages = true;
            display-inlay-hints = true;
          };

          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "block";
          };

          file-picker.max-depth = 10;

          whitespace = {
            render = {
              space = "all";
              tab = "all";
              nbsp = "all";
              nnbsp = "all";
              newline = "none";
            };

            characters = {
              space = "·";
              nbsp = "⍽";
              nnbsp = "␣";
              tab = "→";
              tabpad = "·";
            };
          };

          indent-guides = {
            render = true;
            character = "│";
            skip-levels = 1;
          };

          inline-diagnostics = {
            cursor-line = "warning";
            other-lines = "error";
            max-diagnostics = 3;
          };
        };
      };
    };
  };
}
