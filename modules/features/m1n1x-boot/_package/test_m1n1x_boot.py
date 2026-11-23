"""PAYLOADS_PY enables the contract tests against the installer's payloads.py."""
import gzip
import importlib.util
import io
import os
from pathlib import Path
import struct
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr

SPEC = importlib.util.spec_from_file_location('m1n1x_boot', Path(__file__).with_name('m1n1x-boot.py'))
boot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(boot)

INSTALLER = None
if os.environ.get('PAYLOADS_PY'):
    spec = importlib.util.spec_from_file_location('payloads', os.environ['PAYLOADS_PY'])
    INSTALLER = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(INSTALLER)


def fdt(extra=b'', board=boot.BOARD):
    """A minimal FDT with the board in the root compatible property."""
    strings = b'compatible\0' + extra
    value = board + b'\0apple,t8132\0apple,arm-platform\0'
    structure = (struct.pack('>II', 1, 0) + struct.pack('>III', 3, len(value), 0)
                 + value + bytes(-len(value) % 4) + struct.pack('>II', 2, 9))
    rsv = 40
    off_struct = rsv + 16
    off_strings = off_struct + len(structure)
    total = off_strings + len(strings)
    header = struct.pack('>10I', 0xd00dfeed, total, off_struct, off_strings, rsv, 17, 16, 0,
                         len(strings), len(structure))
    return header + b'\0' * 16 + structure + strings


def cpio(entries):
    """A newc archive, written the way the kernel reads it."""
    out = bytearray()
    for ino, (name, mode, body) in enumerate(list(entries) + [('TRAILER!!!', 0, b'')]):
        encoded = name.encode() + b'\0'
        fields = (ino, mode, 0, 0, 1, 0, len(body), 0, 0, 0, 0, len(encoded), 0)
        out += b'070701' + b''.join(b'%08X' % value for value in fields) + encoded
        out += bytes(-len(out) % 4)
        out += body
        out += bytes(-len(out) % 4)
    return bytes(out)


LOADER = b'M1N1-STAGE2' * 64
NEW_LOADER = b'M1N1-STAGE2-NEW' * 64
KERNEL = gzip.compress(b'kernel image', mtime=0)
NEW_KERNEL = gzip.compress(b'nixos kernel image', mtime=0)
DTB = fdt(b'old')
NEW_DTB = fdt(b'new')
FIRMWARE = cpio([('vendorfw', 0o40755, b''),
                 ('vendorfw/.vendorfw.manifest', 0o100644, b'manifest\n'),
                 ('vendorfw/brcm', 0o40755, b''),
                 ('vendorfw/brcm/fw.bin', 0o100644, b'\x01\x02\x03')])
INITRD = gzip.compress(cpio([('init', 0o100755, b'#!/bin/sh\n')]), mtime=0)
NEW_INITRD = gzip.compress(cpio([('init', 0o100755, b'nixos stage 1\n')]), mtime=0)
PARAMS = 'panic=0 console=tty0 loglevel=4'
NIXOS_ARGS = PARAMS.split() + ['root=fstab', 'loglevel=4']
INSTALLED_ARGS = PARAMS + ' root=fstab init=/nix/store/a-nixos-system/init'


def installed(loader=LOADER, args=INSTALLED_ARGS, kernel=KERNEL, dtb=DTB, initrd=INITRD,
              firmware=FIRMWARE):
    """boot.bin as the installer writes it (payloads.build)."""
    initramfs = initrd + bytes(-len(initrd) % 4) + firmware
    return boot.join({'loader': loader, 'bootargs': boot.BOOTARGS + args.encode() + b'\n',
                      'kernel': kernel, 'dtb': dtb, 'initramfs': initramfs})


def compose(current=None, **overrides):
    values = dict(current=installed() if current is None else current, loader=NEW_LOADER,
                  kernel=NEW_KERNEL, dtb=NEW_DTB, initrd=NEW_INITRD, args=NIXOS_ARGS,
                  init='/nix/store/x-nixos-system/init')
    values.update(overrides)
    return boot.compose(**values)


class Layout(unittest.TestCase):
    def test_parse_join_round_trip(self):
        data = installed()
        self.assertEqual(boot.join(boot.parse(data)), data)

    def test_trailing_byte_refused(self):
        with self.assertRaises(boot.Refused):
            boot.parse(installed() + b'\0')

    def test_split_installer_initramfs(self):
        initrd, firmware = boot.split_initramfs(boot.parse(installed())['initramfs'])
        self.assertEqual((initrd, firmware), (INITRD, FIRMWARE))
        self.assertIn('vendorfw/brcm/fw.bin', boot.check_firmware(firmware))

    def test_firmware_without_manifest_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'vendorfw.manifest'):
            boot.check_firmware(cpio([('vendorfw', 0o40755, b'')]))

    def test_firmware_outside_vendorfw_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'outside'):
            boot.check_firmware(cpio([('vendorfw/.vendorfw.manifest', 0o100644, b'm'),
                                      ('init', 0o100755, b'x')]))

    def test_truncated_firmware_refused(self):
        with self.assertRaises(boot.Refused):
            boot.split_initramfs(INITRD + bytes(-len(INITRD) % 4) + FIRMWARE[:-200])


class Compose(unittest.TestCase):
    def test_generation_parts_replaced_firmware_kept(self):
        data, _ = compose()
        layout = boot.parse(data)
        self.assertEqual(layout['loader'], NEW_LOADER)
        self.assertEqual(layout['kernel'], NEW_KERNEL)
        self.assertEqual(layout['dtb'], NEW_DTB)
        self.assertEqual(boot.split_initramfs(layout['initramfs']), (NEW_INITRD, FIRMWARE))

    def test_bootargs_are_the_generation_params(self):
        data, _ = compose()
        line = boot.parse(data)['bootargs'].decode()
        self.assertEqual(line, 'chosen.bootargs=' + PARAMS +
                         ' root=fstab init=/nix/store/x-nixos-system/init\n')

    def test_init_in_params_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'init='):
            compose(args=NIXOS_ARGS + ['init=/bin/sh'])

    def test_relative_init_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'absolute Nix store path'):
            compose(init='boot-artifacts/init')

    def test_recompose_is_stable(self):
        first, _ = compose()
        self.assertEqual(compose(current=first)[0], first)

    def test_new_params_apply_on_recompose(self):
        first, _ = compose()
        second, _ = compose(current=first, args=NIXOS_ARGS + ['quiet'])
        self.assertIn(b' quiet init=', boot.parse(second)['bootargs'])

    def test_zstd_initrd_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'gzip'):
            compose(initrd=b'\x28\xb5\x2f\xfd' + b'zstd frame')

    def test_kernel_format_checked(self):
        with self.assertRaisesRegex(boot.Refused, 'gzip member'):
            compose(kernel=b'not gzip')

    def test_other_board_devicetree_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'apple,j713'):
            compose(dtb=fdt().replace(b'apple,j713', b'apple,j715'))

    def test_mini_generation_parts_replaced(self):
        mini = fdt(board=b'apple,j773g')
        data, _ = compose(current=installed(dtb=mini), dtb=mini)
        self.assertEqual(boot.parse(data)['dtb'], mini)
        self.assertEqual(boot.split_initramfs(boot.parse(data)['initramfs'])[1], FIRMWARE)

    def test_mini_migrates_legacy_wifi_firmware_aliases(self):
        mini = fdt(board=b'apple,j773g')
        old_names = [
            'brcm/brcmfmac4388c0-pcie.bin',
            'brcm/brcmfmac4388c0-pcie.txt',
            'brcm/brcmfmac4388c0-pcie.clm_blob',
            'brcm/brcmfmac4388c0-pcie.txcap_blob',
            'brcm/brcmfmac4388c0-pcie.sig',
        ]
        entries = [('vendorfw', 0o40755, b''),
                   ('vendorfw/.vendorfw.manifest', 0o100644,
                    ''.join(f'FILE {name} SHA256 test\n' for name in old_names).encode()),
                   ('vendorfw/brcm', 0o40755, b'')]
        entries.extend(
            (f'vendorfw/{name}', 0o100644, f'firmware-{index}'.encode())
            for index, name in enumerate(old_names)
        )
        legacy_firmware = cpio(entries)

        data, _ = compose(
            current=installed(dtb=mini, firmware=legacy_firmware),
            dtb=mini,
        )
        migrated = boot.split_initramfs(boot.parse(data)['initramfs'])[1]
        names = boot.cpio_names(migrated)

        self.assertTrue(any('4388c2-pcie.bin' in name for name in names))
        self.assertFalse(any('4388c0-pcie' in name for name in names))
        self.assertIn(b'FILE brcm/brcmfmac4388c2-pcie.bin SHA256 test', migrated)
        self.assertNotIn(b'brcmfmac4388c0-pcie', migrated)
        self.assertEqual(compose(current=data, dtb=mini)[0], data)

    def test_air_does_not_migrate_legacy_mini_firmware_aliases(self):
        legacy_firmware = cpio([
            ('vendorfw', 0o40755, b''),
            ('vendorfw/.vendorfw.manifest', 0o100644, b'manifest\n'),
            ('vendorfw/brcm/brcmfmac4388c0-pcie.bin', 0o100644, b'firmware'),
        ])
        data, _ = compose(current=installed(firmware=legacy_firmware))
        preserved = boot.split_initramfs(boot.parse(data)['initramfs'])[1]
        self.assertEqual(preserved, legacy_firmware)

    def test_cannot_switch_between_supported_boards(self):
        mini = fdt(board=b'apple,j773g')
        for current, new in ((DTB, mini), (mini, DTB)):
            with self.subTest(board=boot.dtb_board(current)):
                with self.assertRaisesRegex(boot.Refused, 'does not match'):
                    compose(current=installed(dtb=current), dtb=new)

    def test_board_name_outside_root_compatible_is_not_accepted(self):
        with self.assertRaises(boot.Refused):
            boot.dtb_board(fdt(extra=b'apple,j713\0', board=b'apple,j715'))

    def test_ambiguous_board_is_not_accepted(self):
        with self.assertRaises(boot.Refused):
            boot.dtb_board(fdt(board=b'apple,j713\0apple,j773g'))

    def test_truncated_devicetree_structure_refused(self):
        with self.assertRaises(boot.Refused):
            boot.dtb_board(DTB[:-1])

    def test_oversized_loader_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'too large'):
            compose(loader=b'\0' * (boot.LIMITS['loader'] + 1))

    def test_overlong_bootargs_refused(self):
        with self.assertRaisesRegex(boot.Refused, 'exceed'):
            compose(args=NIXOS_ARGS + ['x' * 1100])


@unittest.skipIf(INSTALLER is None, 'PAYLOADS_PY is not set')
class InstallerContract(unittest.TestCase):
    """boot.bin from the installer's own payloads.build must read back and recompose."""

    def installer_bootbin(self, loader, kernel, dtb, initrd, args):
        parts = {'m1n1': loader, 'kernel': kernel, 'dtb': dtb, 'initramfs': initrd}
        return INSTALLER.build(parts, args, FIRMWARE)

    def test_installer_output_parses_and_splits(self):
        data = self.installer_bootbin(LOADER, KERNEL, DTB, INITRD, INSTALLED_ARGS)
        self.assertEqual(data, installed())
        self.assertEqual(boot.split_initramfs(boot.parse(data)['initramfs']), (INITRD, FIRMWARE))

    def test_recompose_matches_what_the_installer_would_write(self):
        data, _ = compose(current=installed())
        expected = self.installer_bootbin(NEW_LOADER, NEW_KERNEL, NEW_DTB, NEW_INITRD,
                                          PARAMS + ' root=fstab init=/nix/store/x-nixos-system/init')
        self.assertEqual(data, expected)

    def test_mini_installer_output_recomposes_unchanged(self):
        mini = fdt(board=b'apple,j773g')
        data = self.installer_bootbin(LOADER, KERNEL, mini, INITRD, INSTALLED_ARGS)
        again, _ = boot.compose(data, LOADER, KERNEL, mini, INITRD, PARAMS.split() + ['root=fstab'],
                                '/nix/store/a-nixos-system/init')
        self.assertEqual(data, again)


class Install(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.efi = root / 'efi'
        self.dir = self.efi / boot.BOOT_DIR
        self.dir.mkdir(parents=True)
        self.boot = self.dir / 'boot.bin'
        self.boot.write_bytes(installed())
        self.toplevel = root / 'system'
        (self.toplevel / 'dtbs' / 'apple').mkdir(parents=True)
        (self.toplevel / 'm1n1.bin').write_bytes(NEW_LOADER)
        (self.toplevel / 'kernel').write_bytes(NEW_KERNEL)
        (self.toplevel / boot.DTB).write_bytes(NEW_DTB)
        (self.toplevel / 'initrd').write_bytes(NEW_INITRD)
        (self.toplevel / 'kernel-params').write_text(' '.join(NIXOS_ARGS))
        self.saved_store = boot.STORE
        boot.STORE = str(root.resolve()) + '/'
        self.link = root / 'system-1-link'
        self.link.symlink_to(self.toplevel)
        self.sys = root / 'sys'
        (self.sys / 'proc' / 'device-tree').mkdir(parents=True)
        (self.sys / 'proc' / 'device-tree' / 'compatible').write_bytes(b'apple,j713\0apple,t8132\0apple,arm-platform\0')

    def tearDown(self):
        boot.STORE = self.saved_store
        self.tmp.cleanup()

    def run_tool(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            status = boot.main(['install', str(self.link), '--efi', str(self.efi),
                                '--sys-root', str(self.sys), *extra])
        return status, out.getvalue(), err.getvalue()

    def test_dry_run_writes_nothing(self):
        before = self.boot.read_bytes()
        status, out, _ = self.run_tool()
        self.assertEqual(status, 0)
        self.assertIn('Dry run', out)
        self.assertEqual(self.boot.read_bytes(), before)
        self.assertEqual(sorted(os.listdir(self.dir)), ['boot.bin'])

    def test_apply_keeps_original_once_and_boots_store_path(self):
        original = self.boot.read_bytes()
        self.assertEqual(self.run_tool('--apply')[0], 0)
        self.assertEqual((self.dir / 'boot.bin.original').read_bytes(), original)
        layout = boot.parse(self.boot.read_bytes())
        self.assertEqual(layout['loader'], NEW_LOADER)
        self.assertIn('init=' + str(self.toplevel.resolve() / 'init'), layout['bootargs'].decode())
        self.assertFalse((self.dir / 'boot.bin.previous').exists())
        (self.toplevel / 'kernel-params').write_text(' '.join(NIXOS_ARGS + ['quiet']))
        first = self.boot.read_bytes()
        self.assertEqual(self.run_tool('--apply')[0], 0)
        self.assertEqual((self.dir / 'boot.bin.original').read_bytes(), original)
        self.assertEqual((self.dir / 'boot.bin.previous').read_bytes(), first)
        (self.toplevel / 'kernel-params').write_text(' '.join(NIXOS_ARGS))
        second = self.boot.read_bytes()
        self.assertEqual(self.run_tool('--apply')[0], 0)
        self.assertEqual((self.dir / 'boot.bin.previous').read_bytes(), second)
        self.assertEqual(sorted(os.listdir(self.dir)), ['boot.bin', 'boot.bin.original', 'boot.bin.previous'])

    def with_free_space(self, size):
        saved = boot.free_space
        boot.free_space = lambda path: size
        self.addCleanup(setattr, boot, 'free_space', saved)

    def test_first_apply_needs_room_for_two_files(self):
        current = len(self.boot.read_bytes())
        new = len(boot.compose(self.boot.read_bytes(), **boot.read_toplevel(self.link))[0])
        self.with_free_space(current + new + boot.MARGIN - 1)
        before = self.boot.read_bytes()
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 1)
        self.assertIn('Not enough free space on the EFI partition', err)
        self.assertIn('MB needed', err)
        self.assertEqual(sorted(os.listdir(self.dir)), ['boot.bin'])
        self.assertEqual(self.boot.read_bytes(), before)
        self.with_free_space(current + new + boot.MARGIN)
        self.assertEqual(self.run_tool('--apply')[0], 0)

    def test_old_previous_counts_as_free(self):
        self.assertEqual(self.run_tool('--apply')[0], 0)
        (self.toplevel / 'kernel-params').write_text(' '.join(NIXOS_ARGS + ['quiet']))
        self.assertEqual(self.run_tool('--apply')[0], 0)
        previous = (self.dir / 'boot.bin.previous').stat().st_size
        (self.toplevel / 'kernel-params').write_text(' '.join(NIXOS_ARGS))
        current = len(self.boot.read_bytes())
        new = len(boot.compose(self.boot.read_bytes(), **boot.read_toplevel(self.link))[0])
        self.with_free_space(current + new + boot.MARGIN - previous)
        self.assertEqual(self.run_tool('--apply')[0], 0)

    def test_interrupted_write_is_cleaned_up(self):
        (self.dir / 'boot.bin.m1n1x-tmp').write_bytes(b'partial')
        self.assertEqual(self.run_tool('--apply')[0], 0)
        self.assertEqual(sorted(os.listdir(self.dir)), ['boot.bin', 'boot.bin.original'])

    def test_already_current_is_left_alone(self):
        self.assertEqual(self.run_tool('--apply')[0], 0)
        status, out, _ = self.run_tool('--apply')
        self.assertEqual(status, 0)
        self.assertIn('already this generation', out)

    def test_other_board_refused_before_writing(self):
        (self.sys / 'proc' / 'device-tree' / 'compatible').write_bytes(b'apple,j715\0apple,t8132\0')
        before = self.boot.read_bytes()
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 1)
        self.assertIn('apple,j713', err)
        self.assertEqual(self.boot.read_bytes(), before)
        self.assertFalse((self.dir / 'boot.bin.original').exists())

    def test_other_board_refused_even_when_already_current(self):
        self.assertEqual(self.run_tool('--apply')[0], 0)
        (self.sys / 'proc' / 'device-tree' / 'compatible').write_bytes(b'linux,dummy-virt\0')
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 1)
        self.assertIn('apple,j713', err)

    def test_mini_apply_uses_mini_devicetree(self):
        mini = fdt(board=b'apple,j773g')
        self.boot.write_bytes(installed(dtb=mini))
        (self.sys / 'proc/device-tree/compatible').write_bytes(b'apple,j773g\0apple,t8132\0')
        (self.toplevel / boot.BOARDS[b'apple,j773g']).write_bytes(mini)
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 0, err)
        self.assertEqual(boot.parse(self.boot.read_bytes())['dtb'], mini)

    def test_running_board_must_match_installed_board(self):
        (self.sys / 'proc/device-tree/compatible').write_bytes(b'apple,j773g\0apple,t8132\0')
        before = self.boot.read_bytes()
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 1)
        self.assertIn('does not match the running board', err)
        self.assertEqual(self.boot.read_bytes(), before)
        self.assertFalse((self.dir / 'boot.bin.original').exists())

    def test_mini_cannot_use_air_only_generation(self):
        mini = fdt(board=b'apple,j773g')
        self.boot.write_bytes(installed(dtb=mini))
        before = self.boot.read_bytes()
        status, _, err = self.run_tool()
        self.assertEqual(status, 1)
        self.assertIn('t8132-j773g.dtb', err)
        self.assertEqual(self.boot.read_bytes(), before)

    def test_misnamed_devicetree_refused_before_writing(self):
        mini = fdt(board=b'apple,j773g')
        self.boot.write_bytes(installed(dtb=mini))
        (self.sys / 'proc/device-tree/compatible').write_bytes(b'apple,j773g\0apple,t8132\0')
        (self.toplevel / boot.BOARDS[b'apple,j773g']).write_bytes(NEW_DTB)
        before = self.boot.read_bytes()
        status, _, err = self.run_tool('--apply')
        self.assertEqual(status, 1)
        self.assertIn('does not match the installed board', err)
        self.assertEqual(self.boot.read_bytes(), before)
        self.assertFalse((self.dir / 'boot.bin.original').exists())

    def test_generation_without_m1n1_refused(self):
        (self.toplevel / 'm1n1.bin').unlink()
        status, _, err = self.run_tool()
        self.assertEqual(status, 1)
        self.assertIn('m1n1.bin', err)

    def test_not_a_store_path_refused(self):
        self.link.unlink()
        self.link.symlink_to('/tmp')
        status, _, err = self.run_tool()
        self.assertEqual(status, 1)
        self.assertIn('not a NixOS generation', err)


if __name__ == '__main__':
    unittest.main()
