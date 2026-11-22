{
  lib,
  stdenvNoCC,
  python3,
  installerSource,
}:
stdenvNoCC.mkDerivation {
  pname = "m1n1x-boot";
  version = "0.4.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./m1n1x-boot.py
      ./test_m1n1x_boot.py
    ];
  };

  nativeBuildInputs = [ python3 ];
  buildInputs = [ python3 ];

  PAYLOADS_PY = "${installerSource}/src/payloads.py";

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -I -m unittest discover -s . -p 'test_*.py' -v 2>&1 | tee test.log
    grep -q 'skipped' test.log && { echo "contract tests did not run" >&2; exit 1; }
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 m1n1x-boot.py $out/bin/m1n1x-boot
    install -Dm644 m1n1x-boot.py $out/share/m1n1x-boot/m1n1x-boot.py
    patchShebangs --host $out/bin/m1n1x-boot
    runHook postInstall
  '';

  meta = {
    description = "Write the J713 or J773G m1n1 boot.bin for a m1n1x NixOS generation";
    license = lib.licenses.mit;
    mainProgram = "m1n1x-boot";
    platforms = lib.platforms.linux;
  };
}
