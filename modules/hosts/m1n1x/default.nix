{
  moduleWithSystem,
  self,
  inputs,
  ...
}:
{
  flake.nixosConfigurations.m1n1x = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = with self.nixosModules; [
      m1n1xSystem
      core
      librewolf
      (moduleWithSystem (
        { self', pkgs, ... }: {
          networking.hostName = "m1n1x";
          hardware.m1n1x.board = "j773g";
          environment.systemPackages = with pkgs; [
            self'.packages.helix
            git
            gitui
            nh
          ];
          fonts.packages = with pkgs; [
            nerd-fonts.jetbrains-mono
          ];
        }
      ))
    ];
  };
}
