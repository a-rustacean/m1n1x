{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.opencode = inputs.wrappers.wrappers.opencode.wrap {
      inherit pkgs;
      env."OPENCODE_CLI_CONFIG_CONTENT" = builtins.readFile ./cli.json;
    };
  };
}
