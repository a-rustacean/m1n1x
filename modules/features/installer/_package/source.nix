{
  lib,
  applyPatches,
  fetchFromGitHub,
}:
applyPatches {
  name = "gravity-installer-m1n1x";
  src = fetchFromGitHub {
    owner = "GravityLinux";
    repo = "installer";
    # Latest air-j713 branch: both boards and their radio firmware profiles.
    rev = "f54140ea4957363c6fcdd8f1699b2e38730603ab";
    hash = "sha256-F4fRn+WtFQ+R1rWxMNrUkg+Ej63LZdnfXmcSrdli+6k=";
  };
  patches = lib.filesystem.listFilesRecursive ./patches;
}
