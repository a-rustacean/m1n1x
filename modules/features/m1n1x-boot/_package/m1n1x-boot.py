#!/usr/bin/env python3
"""Write <ESP>/m1n1/boot.bin for a NixOS generation, keeping its firmware.

Layout, as the installer's payloads.py writes it:

    m1n1 stage 2
    chosen.bootargs=<one printable line>\\n
    gzip kernel
    flattened devicetree
    m1n1_initramfs <u32 LE length> <gzip initrd> <zero pad to 4> <firmware cpio>

m1n1 stage 1 appends its variables at boot, so they are not in the file.
"""
import argparse
import hashlib
import os
from pathlib import Path
import struct
import sys
import zlib

BOARD = b'apple,j713'
BOARDS = {
    BOARD: 'dtbs/apple/t8132-j713.dtb',
    b'apple,j773g': 'dtbs/apple/t8132-j773g.dtb',
}
BOOTARGS = b'chosen.bootargs='
GZIP = b'\x1f\x8b\x08'
FDT_MAGIC = b'\xd0\x0d\xfe\xed'
INITRAMFS = b'm1n1_initramfs'
MAX_BOOTARGS = 1024
LIMITS = {'loader': 4 << 20, 'kernel': 64 << 20, 'dtb': 2 << 20, 'initrd': 128 << 20,
          'firmware': 128 << 20}
FIRMWARE_DIR = 'vendorfw'
FIRMWARE_MANIFEST = 'vendorfw/.vendorfw.manifest'
CPIO_MAGIC = b'070701'
TRAILER = 'TRAILER!!!'
MARGIN = 1 << 20
STORE = '/nix/store/'
BOOT_DIR = 'm1n1'
DTB = BOARDS[BOARD]
ORIGINAL = 'boot.bin.original'
PREVIOUS = 'boot.bin.previous'


class Refused(Exception):
    pass


def require(condition, message):
    if not condition:
        raise Refused(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def gzip_end(data, start):
    stream = zlib.decompressobj(31)
    try:
        stream.decompress(memoryview(data)[start:])
    except zlib.error:
        return None
    if not stream.eof:
        return None
    return len(data) - len(stream.unused_data)


def fdt_size(data, offset):
    if data[offset:offset + 4] != FDT_MAGIC or offset + 40 > len(data):
        return None
    total, structure, strings, _, version, last = struct.unpack_from('>6I', data, offset + 4)
    if not (40 <= total <= len(data) - offset and version >= 16 and last <= 16 and
            structure < total and strings < total):
        return None
    return total


def board_from_compatible(compatible):
    matches = [board for board in BOARDS if board in compatible.split(b'\0')]
    require(len(matches) == 1, 'Expected exactly one supported board: apple,j713 or apple,j773g')
    return matches[0]


def dtb_board(dtb):
    """Read the root compatible property, never a child node or an arbitrary string."""
    require(fdt_size(dtb, 0) == len(dtb), 'Devicetree is not one flattened devicetree')
    _, _, position, strings, _, _, _, _, strings_size, structure_size = struct.unpack_from('>10I', dtb)
    end = position + structure_size
    require(end <= len(dtb) and strings + strings_size <= len(dtb), 'Invalid devicetree blocks')
    names = dtb[strings:strings + strings_size]
    compatible, depth, started = None, 0, False
    while position + 4 <= end:
        token, = struct.unpack_from('>I', dtb, position)
        position += 4
        if token == 1:  # FDT_BEGIN_NODE
            name_end = dtb.find(b'\0', position, end)
            require(name_end >= position, 'Unterminated devicetree node name')
            if not started:
                require(name_end == position, 'Invalid devicetree root')
                started = True
            else:
                require(depth > 0, 'Multiple devicetree roots')
            position = (name_end + 4) & ~3
            depth += 1
        elif token == 2:  # FDT_END_NODE
            require(depth > 0, 'Unbalanced devicetree nodes')
            depth -= 1
        elif token == 3:  # FDT_PROP
            require(depth > 0 and position + 8 <= end, 'Invalid devicetree property')
            length, name = struct.unpack_from('>II', dtb, position)
            position += 8
            name_end = names.find(b'\0', name)
            require(name < len(names) and name_end >= name and position + length <= end,
                    'Invalid devicetree property bounds')
            if depth == 1 and names[name:name_end] == b'compatible':
                require(compatible is None, 'Duplicate root compatible property')
                compatible = dtb[position:position + length]
            position = (position + length + 3) & ~3
        elif token == 4:  # FDT_NOP
            pass
        elif token == 9:  # FDT_END
            require(started and depth == 0 and compatible is not None and compatible.endswith(b'\0'),
                    'Missing root compatible property or incomplete devicetree')
            return board_from_compatible(compatible)
        else:
            raise Refused('Unknown devicetree token')
    raise Refused('Incomplete devicetree structure')


def parse_at(data, start):
    end = data.find(b'\n', start)
    if start == 0 or end < 0:
        return None
    line = data[start:end + 1]
    if not all(32 <= byte < 127 for byte in line[:-1]):
        return None
    kernel = end + 1
    if data[kernel:kernel + 3] != GZIP:
        return None
    dtb = gzip_end(data, kernel)
    if dtb is None:
        return None
    size = fdt_size(data, dtb)
    if size is None:
        return None
    tag = dtb + size
    if data[tag:tag + len(INITRAMFS)] != INITRAMFS or tag + len(INITRAMFS) + 4 > len(data):
        return None
    length, = struct.unpack_from('<I', data, tag + len(INITRAMFS))
    body = tag + len(INITRAMFS) + 4
    if body + length != len(data):
        return None
    return {'loader': data[:start], 'bootargs': line, 'kernel': data[kernel:dtb],
            'dtb': data[dtb:tag], 'initramfs': data[body:]}


def parse(data):
    """Split boot.bin; exactly one layout must consume the whole file."""
    found, position = [], data.find(BOOTARGS)
    while position >= 0:
        layout = parse_at(data, position)
        if layout is not None:
            found.append(layout)
        position = data.find(BOOTARGS, position + 1)
    require(len(found) == 1, 'boot.bin does not have the expected loader, boot arguments, '
            'kernel, devicetree and initramfs layout')
    return found[0]


def join(layout):
    initramfs = layout['initramfs']
    return b''.join((layout['loader'], layout['bootargs'], layout['kernel'], layout['dtb'],
                     INITRAMFS, struct.pack('<I', len(initramfs)), initramfs))


def split_initramfs(initramfs):
    """Return (gzip initrd, firmware cpio) from the installer's initramfs layout."""
    require(initramfs[:3] == GZIP, 'The initramfs does not start with a gzip initrd')
    end = gzip_end(initramfs, 0)
    require(end is not None, 'The initrd is not one complete gzip member')
    start = end + (-end % 4)
    require(initramfs[end:start] == b'\0' * (start - end), 'Unexpected bytes after the initrd')
    firmware = initramfs[start:]
    require(firmware.startswith(CPIO_MAGIC) and (TRAILER + '\0').encode() in firmware[-124:],
            'The firmware after the initrd is not one complete newc archive')
    return initramfs[:end], firmware


def cpio_names(data):
    """Names in one newc archive, checking its structure to the trailer."""
    names, position = [], 0
    while True:
        require(data[position:position + 6] == CPIO_MAGIC, 'Corrupt firmware cpio')
        require(position + 110 <= len(data), 'Truncated firmware cpio header')
        fields = [int(data[position + 6 + 8 * i:position + 14 + 8 * i], 16) for i in range(13)]
        filesize, namesize = fields[6], fields[11]
        start = position + 110
        require(namesize >= 1 and start + namesize <= len(data), 'Truncated firmware cpio name')
        name = data[start:start + namesize - 1].decode('utf-8', 'surrogateescape')
        body = (start + namesize + 3) & ~3
        position = (body + filesize + 3) & ~3
        require(body + filesize <= len(data), 'Truncated firmware cpio body')
        if name == TRAILER:
            require(data[position:].strip(b'\0') == b'', 'Data after the firmware cpio trailer')
            return names
        names.append(name.lstrip('/'))


def check_firmware(firmware):
    names = cpio_names(firmware)
    require(FIRMWARE_MANIFEST in names, 'The firmware archive has no ' + FIRMWARE_MANIFEST)
    require(all(name == FIRMWARE_DIR or name.startswith(FIRMWARE_DIR + '/') for name in names),
            'The firmware archive has files outside /' + FIRMWARE_DIR)
    return names


def bootargs_line(args, init):
    require(not any(arg.startswith('init=') for arg in args), 'Kernel parameters already set init=')
    unique = list(dict.fromkeys(args))
    line = BOOTARGS + ' '.join(unique + ['init=' + init]).encode() + b'\n'
    require(len(line) - len(BOOTARGS) - 1 <= MAX_BOOTARGS,
            f'Boot arguments exceed {MAX_BOOTARGS} characters')
    require(all(32 <= byte < 127 for byte in line[:-1]), 'Boot arguments must be printable ASCII')
    return line


def compose(current, loader, kernel, dtb, initrd, args, init):
    """Return (new boot.bin bytes, report lines): the generation's parts with
    the firmware from the current boot.bin."""
    layout = parse(current)
    current_board = dtb_board(layout['dtb'])
    _, firmware = split_initramfs(layout['initramfs'])
    names = check_firmware(firmware)
    require(len(firmware) <= LIMITS['firmware'], 'The firmware archive is too large')

    require(0 < len(loader) <= LIMITS['loader'], 'm1n1 stage 2 is empty or too large')
    require(kernel[:3] == GZIP and gzip_end(kernel, 0) == len(kernel), 'Kernel is not one gzip member')
    require(len(kernel) <= LIMITS['kernel'], 'The kernel is larger than the installer allows')
    require(fdt_size(dtb, 0) == len(dtb), 'Devicetree is not one flattened devicetree')
    require(len(dtb) <= LIMITS['dtb'], 'The devicetree is larger than the installer allows')
    require(dtb_board(dtb) == current_board,
            'Devicetree does not match the installed board ' + current_board.decode())
    require(initrd[:3] == GZIP and gzip_end(initrd, 0) == len(initrd),
            'The initrd must be one gzip member (boot.initrd.compressor = "gzip")')
    require(len(initrd) <= LIMITS['initrd'], 'The initrd is larger than the installer allows')

    initramfs = initrd + bytes(-len(initrd) % 4) + firmware
    new = {'loader': loader, 'bootargs': bootargs_line(args, init), 'kernel': kernel,
           'dtb': dtb, 'initramfs': initramfs}
    data = join(new)
    check = parse(data)
    require(all(check[name] == new[name] for name in new), 'Composed boot.bin does not read back')
    require(split_initramfs(check['initramfs']) == (initrd, firmware), 'Composed initramfs does not split back')

    report = [
        f'loader     {sha(loader)}  {len(loader)} bytes',
        f'kernel     {sha(kernel)}  {len(kernel)} bytes',
        f'devicetree {sha(dtb)}  {len(dtb)} bytes',
        f'initrd     {sha(initrd)}  {len(initrd)} bytes',
        f'firmware   {len(names)} entries, {len(firmware)} bytes, kept from the installed boot.bin',
        'bootargs   ' + new['bootargs'][len(BOOTARGS):-1].decode(),
    ]
    return data, report


def temporary(path):
    return path.with_name(path.name + '.m1n1x-tmp')


def write_file(path, data):
    with open(temporary(path), 'wb') as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary(path), path)


def free_space(path):
    stat = os.statvfs(path)
    return stat.f_bavail * stat.f_frsize


def megabytes(size):
    return -(-size // 1000000)


def sync_dir(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def check_board(sys_root):
    compatible = Path(sys_root, 'proc/device-tree/compatible')
    require(compatible.is_file(), 'Cannot read the running board from ' + str(compatible))
    return board_from_compatible(compatible.read_bytes())


def read_toplevel(toplevel, board=BOARD):
    # init= must name the store path, not the profile link.
    toplevel = Path(os.path.realpath(toplevel))
    require(str(toplevel).startswith(STORE), f'{toplevel} is not a NixOS generation in {STORE}')
    require((toplevel / 'm1n1.bin').is_file(), f'{toplevel} has no m1n1.bin')
    return {
        'loader': (toplevel / 'm1n1.bin').read_bytes(),
        'kernel': (toplevel / 'kernel').read_bytes(),
        'dtb': (toplevel / BOARDS[board]).read_bytes(),
        'initrd': (toplevel / 'initrd').read_bytes(),
        'args': (toplevel / 'kernel-params').read_text().split(),
        'init': str(toplevel / 'init'),
    }


def install(args):
    running_board = check_board(args.sys_root) if args.apply else None
    boot = Path(args.efi, BOOT_DIR, 'boot.bin')
    require(boot.is_file() and not boot.is_symlink(), f'{boot} is missing (is the ESP mounted at {args.efi}?)')
    current = boot.read_bytes()
    board = dtb_board(parse(current)['dtb'])
    require(running_board is None or running_board == board,
            'Installed boot.bin does not match the running board')
    data, report = compose(current, **read_toplevel(args.toplevel, board))
    print('\n'.join(report))
    if data == current:
        print('boot.bin is already this generation')
        return
    if not args.apply:
        print(f'Dry run: would write {len(data)} bytes to {boot}. Pass --apply to write it.')
        return

    original = boot.with_name(ORIGINAL)
    previous = boot.with_name(PREVIOUS)
    for path in (boot, original, previous):
        temporary(path).unlink(missing_ok=True)
    # FAT has no links: each kept file is a full copy, and boot.bin.original
    # stays the fallback while boot.bin.previous is replaced.
    first = not original.exists()
    freed = 0 if first or not previous.exists() else previous.stat().st_size
    need = len(current) + len(data) + MARGIN
    free = free_space(boot.parent) + freed
    require(free >= need, f'Not enough free space on the EFI partition: '
            f'{megabytes(need)} MB needed, {megabytes(free)} MB free')
    if first:
        write_file(original, current)
        print(f'Kept the installed boot.bin as {original}')
    else:
        previous.unlink(missing_ok=True)
        write_file(previous, current)
    write_file(boot, data)
    sync_dir(boot.parent)
    require(boot.read_bytes() == data, 'boot.bin did not read back after writing')
    print(f'Wrote {boot}; the replaced file is {original if first else previous}')


def inspect(args):
    layout = parse(Path(args.file).read_bytes())
    print(f'loader     {sha(layout["loader"])}  {len(layout["loader"])} bytes')
    print(f'kernel     {sha(layout["kernel"])}  {len(layout["kernel"])} bytes')
    print(f'devicetree {sha(layout["dtb"])}  {len(layout["dtb"])} bytes')
    print('bootargs   ' + layout['bootargs'][len(BOOTARGS):-1].decode())
    try:
        initrd, firmware = split_initramfs(layout['initramfs'])
        print(f'initrd     {sha(initrd)}  {len(initrd)} bytes')
        print(f'firmware   {len(check_firmware(firmware))} entries under /{FIRMWARE_DIR}')
    except Refused as error:
        print(f'initramfs  {error}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    commands = parser.add_subparsers(dest='command', required=True)
    show = commands.add_parser('inspect', help='describe a boot.bin')
    show.add_argument('file')
    show.set_defaults(run=inspect)
    put = commands.add_parser('install', help='compose boot.bin for a NixOS generation')
    put.add_argument('toplevel', help='the generation (/nix/var/nix/profiles/system-N-link)')
    put.add_argument('--efi', default='/boot/efi', help='ESP mount point (default /boot/efi)')
    put.add_argument('--apply', action='store_true', help='write boot.bin (default: dry run)')
    put.add_argument('--sys-root', default='/', help=argparse.SUPPRESS)
    put.set_defaults(run=install)
    args = parser.parse_args(argv)
    try:
        args.run(args)
    except (Refused, OSError) as error:
        print(f'm1n1x-boot: refused: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
