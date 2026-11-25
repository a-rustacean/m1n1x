{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    packages.quickshell = inputs.wrappers.wrappers.quickshell.wrap {
      inherit pkgs;
      configDir = "${./.}";
    };
  };
}
