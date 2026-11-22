# Python, libffi and the CA bundle are the only parts not built from source.
{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  cpio,
  imagemagick,
  libicns,
  nixos-icons,
  cacert,
  m1n1Stage1,
  installerSource,
}:
let
  python = fetchurl {
    url = "https://www.python.org/ftp/python/3.13.9/python-3.13.9-macos11.pkg";
    hash = "sha256-2v6/YrhzfzQfa37KLW0RU6UKaxv7+kuKrw5ircc+UBc=";
  };
  # The registry's anonymous token for public bottles.
  libffi = fetchurl {
    name = "libffi-3.5.2.arm64_tahoe.bottle.tar.gz";
    url = "https://ghcr.io/v2/homebrew/core/libffi/blobs/sha256:564ce412bbf20deb184e488fe9b1cbf94b5c770965e48567c829a5f580141a95";
    hash = "sha256-VkzkErvyDesYTkiP6bHL+Utcdwll5IVnyCml9YAUGpU=";
    curlOptsList = [
      "-H"
      "Authorization: Bearer QQ=="
    ];
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "m1n1x-installer";
  version = "0-unstable-2026-11-11";

  src = installerSource;

  nativeBuildInputs = [
    xar
    cpio
    imagemagick
    libicns
  ];

  buildPhase = ''
    runHook preBuild

    mkdir -p package/bin package/boot
    cp -r src/* package/
    rm package/gravity_firmware
    cp -r gravity_firmware package/
    install -m444 ${m1n1Stage1}/lib/m1n1/m1n1.bin package/boot/m1n1.bin

    for size in 16 32 128 256 512; do
      magick ${nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake-white.png \
        -resize ''${size}x$size logo-$size.png
    done
    png2icns package/logo.icns logo-*.png

    framework=package/Frameworks/Python.framework
    mkdir -p $framework
    mkdir python-package
    xar -x -f ${python} -C python-package
    gzip -dc python-package/Python_Framework.pkg/Payload | (cd $framework && cpio -i --quiet)
    tar -xzf ${libffi}
    mv libffi/3.5.2/lib/libffi*.dylib $framework/Versions/Current/lib/

    # As upstream's build.sh.
    rm -rf $framework/Versions/Current/{include,share}
    (cd $framework/Versions/Current/lib && rm -rf -- tdb* tk* Tk* libtk* *tcl*)
    (cd $framework/Versions/Current/lib/python3.13 && rm -rf test ensurepip idlelib)
    rm -f $framework/Versions/Current/lib/python3.13/lib-dynload/{_test*,_tkinter*}
    install -m444 ${cacert}/etc/ssl/certs/ca-bundle.crt $framework/Versions/Current/etc/openssl/cert.pem

    echo m1n1x-${finalAttrs.version} > package/version.tag

    mkdir notices
    install -m444 LICENSE notices/gravity-installer.txt
    cat ${m1n1Stage1.src}/LICENSE.GPL2 ${m1n1Stage1.src}/LICENSE.MIT > notices/m1n1.txt
    cp -r ${m1n1Stage1.src}/3rdparty_licenses notices/m1n1-3rdparty
    install -m444 $framework/Versions/Current/lib/python3.13/LICENSE.txt notices/python.txt
    install -m444 libffi/3.5.2/LICENSE notices/libffi.txt
    echo "The CA bundle (Frameworks/Python.framework/Versions/Current/etc/openssl/cert.pem) is Mozilla's, under MPL-2.0: https://www.mozilla.org/MPL/2.0/" \
      > notices/ca-bundle.txt

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    tar -C package --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -cf - . \
      | gzip -9n > $out/installer.tar.gz
    cp -r notices $out/notices
    chmod -R u+w $out/notices
    runHook postInstall
  '';

  meta = {
    description = "macOS-side installer for m1n1x on the M4 MacBook Air and Mac mini";
    license = lib.licenses.mit;
  };
})
