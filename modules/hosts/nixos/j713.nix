{ self, inputs, ... }:
{
  flake.nixosConfigurations.j713 = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      self.nixosModules.m1n1xSystem
      {
        networking.hostName = "m4-air";
        hardware.m1n1x.board = "j713";
      }
    ];
  };
}
