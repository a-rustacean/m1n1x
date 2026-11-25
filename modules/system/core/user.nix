{
  flake.nixosModules.user = {
    users.users.dilshad = {
      isNormalUser = true;
      initialPassword = "change-me";
      extraGroups = [
        "root"
        "wheel"
        "networkmanager"
      ];
    };
  };
}
