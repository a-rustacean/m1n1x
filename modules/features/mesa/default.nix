{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      hostSystem = pkgs.stdenv.hostPlatform.system;
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      aarch64 =
        if hostSystem == "aarch64-linux" then
          pkgs
        else if isDarwin then
          import inputs.nixpkgs {
            localSystem = "aarch64-linux";
          }
        else
          import inputs.nixpkgs {
            localSystem = hostSystem;
            crossSystem = "aarch64-linux";
          };
    in
    {
      packages.mesa = aarch64.callPackage ./_package { };
    };
}
