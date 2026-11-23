{ self, inputs, ... }:
{
  flake.nixosConfigurations.j773g = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      self.nixosModules.m1n1xSystem
      {
        networking.hostName = "m4-mini";
        hardware.m1n1x.board = "j773g";
      }
    ];
  };
}
