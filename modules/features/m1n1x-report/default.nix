{ inputs, ... }:
{
  perSystem =
    { pkgs, self', ... }:
    let
      hostSystem = pkgs.stdenv.hostPlatform.system;
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      m1n1xBoot = self'.packages.m1n1x-boot;
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
      packages.m1n1x-report = aarch64.callPackage ./_package {
        inherit m1n1xBoot;
      };
    };
}
