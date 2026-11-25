{ self, ... }:
{
  flake.nixosModules.core = {
    imports = with self.nixosModules; [
      user
      networking
    ];
  };
}
