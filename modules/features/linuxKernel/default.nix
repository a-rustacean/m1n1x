{ inputs, ... }:
{
  perSystem = { pkgs, ... }:
  let
    hostSystem = pkgs.stdenv.hostPlatform.system;
    isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
    aarch64 =
      if hostSystem == "aarch64-linux" then
        pkgs
      else if isDarwin then
        # Kernel build-time tools include Linux-only dependencies. Use a native
        # Linux derivation so Darwin builds route through the Linux builder.
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
    packages.linuxKernel = aarch64.callPackage ./_package {};
  };
}
