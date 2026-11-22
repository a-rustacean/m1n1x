#!/bin/bash
#   bash Install.command --verify-only   check every file in the kit
#   bash Install.command                 check, then start the installer
set -euo pipefail
kit=$(cd "$(dirname "$0")" && pwd -P)

case "${1:-}" in
  "" | --verify-only) ;;
  *) echo 'Usage: bash Install.command [--verify-only]' >&2; exit 2 ;;
esac

echo 'Checking the kit. The OS package takes a minute; wait for its OK line.'
(cd "$kit" && shasum -a 256 -c SHA256SUMS)
[[ "${1:-}" == --verify-only ]] && exit 0

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo 'Run this from native arm64 macOS.' >&2; exit 1; }
case "$(cat "$kit/board")" in
  j713) model=Mac16,12 ;;
  j773g) model=Mac16,10 ;;
  *) echo 'Unknown installer kit board.' >&2; exit 1 ;;
esac
[[ $(/usr/sbin/sysctl -n hw.model) == "$model" ]] ||
  { echo "This kit is for $model; build the kit for your board instead." >&2; exit 1; }

work=$(mktemp -d /private/tmp/m1n1x-install.XXXXXXXX)
tar -xzf "$kit/installer.tar.gz" -C "$work"
cp "$kit/installer_data.json" "$work/"
echo "Installer files: $work"
echo 'The installer runs as root; enter your password if asked.'
exec /usr/bin/caffeinate -dis /usr/bin/sudo /usr/bin/env \
  REPO_BASE="$kit" DISTRO=m1n1x DISTRO_DOCS='GUIDE.md in the installer kit' ${EXPERT:+EXPERT="$EXPERT"} \
  "$work/install.sh"
