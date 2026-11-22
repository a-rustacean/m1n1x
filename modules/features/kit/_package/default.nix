{
  runCommand,
  python3,
  zstd,
  makeExt4Fs,
  toplevel,
  systemLabel,
  board ? "j713",
  rootUuid ? "5b0c6f2e-8d4a-4e1b-9c3f-7a2d1e6b4f80",
  volumeLabel ? "m1n1x",
  installer,
  installerSource,
  m1n1xBoot,
  guide,
  osName ? "m1n1x",
  loader ? "${toplevel}/m1n1.bin",
  kernel ? "${toplevel}/kernel",
  dtb ? "${toplevel}/dtbs/apple/t8132-${board}.dtb",
  initrd ? "${toplevel}/initrd",
  kernelParams ? "${toplevel}/kernel-params",
  init ? "${toplevel}/init",
}:
let
  rootImage = makeExt4Fs {
    storePaths = [ toplevel ];
    inherit volumeLabel;
    uuid = rootUuid;
    compressImage = true;
  };
in
runCommand "m1n1x-kit-${systemLabel}"
  {
    nativeBuildInputs = [
      python3
      zstd
    ];
    passthru = {
      inherit
        rootImage
        toplevel
        systemLabel
        board
        rootUuid
        volumeLabel
        ;
    };
  }
  ''
    # Stage boot inputs before writing the root image, which can trigger
    # automatic GC on the constrained ARM builder.
    mkdir -p boot-artifacts
    cp ${loader} boot-artifacts/m1n1.bin
    cp ${kernel} boot-artifacts/kernel
    cp ${dtb} boot-artifacts/device-tree.dtb
    cp ${initrd} boot-artifacts/initrd
    cp ${kernelParams} boot-artifacts/kernel-params

    python3 -I ${./make-kit.py} \
      --installer ${installer} \
      --installer-src ${installerSource} \
      --board ${board} \
      --m1n1x-boot ${m1n1xBoot}/share/m1n1x-boot/m1n1x-boot.py \
      --root-image-zstd ${rootImage} \
      --loader boot-artifacts/m1n1.bin \
      --kernel boot-artifacts/kernel \
      --dtb boot-artifacts/device-tree.dtb \
      --initrd boot-artifacts/initrd \
      --kernel-params boot-artifacts/kernel-params \
      --init ${init} \
      --os-name ${osName} \
      --install-command ${./Install.command} \
      --preflight ${./preflight.command} \
      --start-here ${./START-HERE.md} \
      --guide ${guide} \
      --out $out
  ''
