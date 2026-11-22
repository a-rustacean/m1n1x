{ inputs, ... }:
{
  perSystem =
    { pkgs, self', ... }:
    let
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      buildPkgs =
        if isDarwin then
          import inputs.nixpkgs {
            localSystem = "aarch64-linux";
          }
        else
          pkgs;
      installerSource = buildPkgs.callPackage ./_package/source.nix { };
      m1n1Stage1 = self'.packages.graviton.override {
        stage = 1;
      };
    in
    {
      packages.m1n1x-installer-source = installerSource;
      packages.m1n1x-installer = buildPkgs.callPackage ./_package {
        inherit installerSource m1n1Stage1;
      };
    };
}
