# Using the m1n1x NixOS module

The flake exports `nixosModules.default` (also available as
`nixosModules.m1n1x`). It supplies the M4 hardware, boot, firmware, and image
configuration. Enable it with `hardware.m1n1x.enable`, then select a board.
Its package options default to this flake's packages and can be overridden
individually.

Follow the m1n1x flake's Nixpkgs input so its packages and the host use the same
Nixpkgs revision:

```nix
inputs.m1n1x = {
  url = "github:a-rustacean/m1n1x";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Compose a host from that reusable module, and override package attributes or
other inputs where needed:

```nix
inputs.nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  specialArgs = { inherit inputs; };
  modules = [
    inputs.m1n1x.nixosModules.default
    ({ inputs, ... }: {
      nixpkgs.hostPlatform = "aarch64-linux";
      hardware.m1n1x = {
        enable = true;
        board = "j773g";
        wifiRegion = "US";
      };

      # For example, take Mesa from another flake input.
      hardware.m1n1x.packages.mesa =
        inputs.mesa.packages.aarch64-linux.default;
    })
  ];
}
```

This repository composes its own hosts under `modules/hosts/nixos/`; the
shared Hyprland profile is `nixosModules.m1n1xSystem`. The J773G installer kit
is built as `m1n1x-kit`. J713 hardware remains supported by the
`hardware.m1n1x` module, but this checkout no longer ships a J713 host.
