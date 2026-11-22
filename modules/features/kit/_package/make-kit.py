#!/usr/bin/env python3
"""Assemble the installer kit and check it with the installer's own code."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

PACKAGE = 'm1n1x-{board}.zip'
# The display driver supports this firmware's DCP interface.
STUB_FIRMWARE = '26.6.2'


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit('make-kit: ' + message)


def zstd_image_size(path):
    process = subprocess.Popen(['zstd', '-d', '-c', path], stdout=subprocess.PIPE)
    size = 0
    try:
        while chunk := process.stdout.read(1 << 20):
            size += len(chunk)
    finally:
        process.stdout.close()
    require(process.wait() == 0, 'could not decompress root image')
    return size


def write_zstd_image(archive, path, padding):
    process = subprocess.Popen(['zstd', '-d', '-c', path], stdout=subprocess.PIPE)
    try:
        with archive.open('root.ext4', 'w', force_zip64=True) as member:
            shutil.copyfileobj(process.stdout, member)
            if padding:
                member.write(bytes(padding))
    finally:
        process.stdout.close()
    require(process.wait() == 0, 'could not decompress root image')


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stand_in_firmware():
    """A minimal firmware archive in the installer's /vendorfw layout."""
    entries = [('vendorfw', 0o40755, b''), ('vendorfw/.vendorfw.manifest', 0o100644, b'stand-in\n')]
    out = bytearray()
    for ino, (name, mode, body) in enumerate(entries + [('TRAILER!!!', 0, b'')]):
        encoded = name.encode() + b'\0'
        fields = (ino, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(encoded), 0)
        out += b'070701' + b''.join(b'%08X' % value for value in fields) + encoded
        out += bytes(-len(out) % 4)
        out += body
        out += bytes(-len(out) % 4)
    return bytes(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--board', choices=('j713', 'j773g'), default='j713')
    for name in ('installer', 'installer-src', 'm1n1x-boot', 'root-image-zstd', 'loader', 'kernel', 'dtb',
                 'initrd', 'kernel-params', 'init', 'os-name', 'install-command', 'preflight',
                 'start-here', 'guide', 'out'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir()

    m1n1x_boot = load('m1n1x_boot', args.m1n1x_boot)
    board = ('apple,' + args.board).encode()
    require(m1n1x_boot.dtb_board(Path(args.dtb).read_bytes()) == board,
            'devicetree does not match --board ' + args.board)
    package_name = PACKAGE.format(board=args.board)
    sys.path.insert(0, str(Path(args.installer_src, 'src')))
    import osinstall
    import payloads

    params = Path(args.kernel_params).read_text().split()
    line = m1n1x_boot.bootargs_line(params, args.init)
    bootargs = line[len(m1n1x_boot.BOOTARGS):-1].decode()

    parts = {
        'm1n1': ('boot/m1n1.bin', args.loader),
        'kernel': ('boot/Image.gz', args.kernel),
        'dtb': (f'boot/t8132-{args.board}.dtb', args.dtb),
        'initramfs': ('boot/initramfs.cpio.gz', args.initrd),
    }
    root_image_bytes = zstd_image_size(args.root_image_zstd)
    mebibyte = 1 << 20
    root_bytes = (root_image_bytes + mebibyte - 1) // mebibyte * mebibyte
    entry = {
        'name': args.os_name + f' (NixOS, {args.board.upper()}, experimental)',
        'default_os_name': args.os_name,
        'expert': False,
        'boot_object': 'm1n1.bin',
        'next_object': 'm1n1/boot.bin',
        'package': package_name,
        'supported_fw': [STUB_FIRMWARE],
        'partitions': [
            {'name': 'EFI', 'type': 'EFI', 'size': '524288000B', 'format': 'fat',
             'copy_firmware': True, 'copy_installer_data': True},
            {'name': 'Root', 'type': 'Linux', 'size': f'{root_bytes}B',
             'expand': True, 'image': 'root.ext4'},
        ],
        'payloads': {'bootargs': bootargs, **{
            name: {'file': file, 'sha256': sha(path)} for name, (file, path) in parts.items()}},
    }

    # Hypervisor development: a bare m1n1 proxy leaves ANS as iBoot set it up,
    # and Gravity's hypervisor needs iBoot to have loaded this firmware.
    tethered = {
        'name': 'm1n1 proxy only (tethered, for development)',
        'default_os_name': 'm1n1 proxy',
        'expert': True,
        'boot_object': 'm1n1.bin',
        'supported_fw': [STUB_FIRMWARE],
        'partitions': [],
    }

    (out / 'os').mkdir()
    package = out / 'os' / package_name
    # ZIP dates start at 1980.
    with zipfile.ZipFile(package, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=1,
                         allowZip64=True, strict_timestamps=False) as archive:
        # Decompress straight into the ZIP. The installer needs a whole-MiB
        # partition image, so pad the stream rather than copying it to disk.
        write_zstd_image(archive, args.root_image_zstd, root_bytes - root_image_bytes)
        for file, path in parts.values():
            archive.write(path, file)
    with zipfile.ZipFile(package) as archive:
        require(archive.testzip() is None, 'ZIP CRC failure')

    os.environ['REPO_BASE'] = str(out)
    installer = osinstall.OSInstaller(None, {'os_list': [entry]}, entry)
    installer.load_package()
    require(installer.payloads is not None, 'the installer did not read the boot payloads')

    # m1n1x-boot must rewrite the installer's boot.bin unchanged.
    firmware = stand_in_firmware()
    m1n1x_boot.check_firmware(firmware)
    bootbin = payloads.build(installer.payloads, bootargs, firmware)
    loaded = installer.payloads
    again, _ = m1n1x_boot.compose(bootbin, loaded['m1n1'], loaded['kernel'], loaded['dtb'],
                                 loaded['initramfs'], params, args.init)
    require(again == bootbin, 'm1n1x-boot would not reproduce the installer boot.bin')

    shutil.copyfile(Path(args.installer, 'installer.tar.gz'), out / 'installer.tar.gz')
    shutil.copytree(Path(args.installer, 'notices'), out / 'notices')
    for name, source, mode in (('Install.command', args.install_command, 0o755),
                               ('preflight.command', args.preflight, 0o755),
                               ('START-HERE.md', args.start_here, 0o644),
                               ('GUIDE.md', args.guide, 0o644)):
        shutil.copyfile(source, out / name)
        os.chmod(out / name, mode)
    (out / 'installer_data.json').write_text(
        json.dumps({'os_list': [entry, tethered]}, indent=2, sort_keys=True) + '\n')
    (out / 'board').write_text(args.board + '\n')

    report = json.dumps({'board': args.board, 'bootargs': bootargs,
                         'bootargs_length': len(bootargs), 'root_bytes': root_bytes,
                         'package_sha256': sha(package),
                         'checks': ['OSInstaller.load_package', 'payloads.read', 'payloads.build',
                                    'm1n1x-boot reproduces the installer boot.bin']},
                        indent=2) + '\n'
    (out / 'BUILD-REPORT.json').write_text(report)

    files = sorted(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file())
    (out / 'SHA256SUMS').write_text(''.join(f'{sha(out / name)}  {name}\n' for name in files))
    print(report, end='')


if __name__ == '__main__':
    main()
