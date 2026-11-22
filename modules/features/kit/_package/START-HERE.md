# m1n1x installer kit

m1n1x is an experimental NixOS for the 13-inch M4 MacBook Air (Mac16,12 /
J713) and M4 Mac mini (Mac16,10 / J773G). Each kit targets one board;
`board` names it and the launcher checks your model. Unfinished audio stays
off. Installation and boot have been reported working on the mini; the Air
retains its existing CPU and GPU thermal limits.

The installer is Gravity Linux's J713/J773G installer, built and adapted by
the m1n1x project. m1n1x is not made, endorsed or supported by Gravity
Linux, Asahi Linux or Apple.

Before installing:

1. Make a full, tested backup of the Mac.
2. Have macOS 26.5 or newer. The installer puts a macOS 26.6.2 stub
   beside it, which the Air needs to boot Linux.
3. Read GUIDE.md in this folder, on another device, before you start.

Then, in Terminal on the target Mac:

```sh
bash preflight.command
bash Install.command --verify-only
bash Install.command
```

The preflight prints the size to type when the installer asks for macOS's
new size. Keep macOS and both recovery environments. Choose the m1n1x entry
and follow the on-screen steps.

To undo: from macOS, delete the partitions the installer created, as
GUIDE.md describes (R2). macOS itself is not changed by the install.

License notices for the installer are in `notices/`.
