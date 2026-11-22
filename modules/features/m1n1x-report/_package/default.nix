{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  gnugrep,
  iproute2,
  util-linux,
  systemd,
  m1n1xBoot,
}:
writeShellApplication {
  name = "m1n1x-report";
  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    iproute2
    util-linux
    systemd
    m1n1xBoot
  ];
  bashOptions = [ ];
  text = lib.readFile ./m1n1x-report.sh;
  meta = {
    description = "Read-only hardware and system report for m1n1x";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
