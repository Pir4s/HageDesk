#!/usr/bin/env bash
# Repackage the rustdesk .deb built by build.py as hagedesk.
#
# On Linux the app derives the systemd unit, the .desktop file and the process
# names it looks for from the lowercase app name, so the binary, the service, the
# install dir and the desktop entries must all be called "hagedesk".
#
# Usage: rebrand-deb.sh <rustdesk.deb> <hagedesk.deb>
set -euo pipefail

src_deb=$(realpath "$1")
out_deb=$(realpath -m "$2")
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

dpkg-deb -R "$src_deb" "$work/pkg"
cd "$work/pkg"

# Install dir and binary. librustdesk.so keeps its name: the binary loads it by that name.
mv usr/share/rustdesk usr/share/hagedesk
mv usr/share/hagedesk/rustdesk usr/share/hagedesk/hagedesk

# systemd unit and polkit helper.
mv usr/share/hagedesk/files/systemd/rustdesk.service usr/share/hagedesk/files/systemd/hagedesk.service
sed -i 's/rustdesk/hagedesk/g; s/RustDesk/HageDesk/g' usr/share/hagedesk/files/systemd/hagedesk.service
if [ -f usr/share/hagedesk/files/polkit ]; then
  sed -i 's/rustdesk/hagedesk/g' usr/share/hagedesk/files/polkit
fi

# Desktop entries.
for f in usr/share/applications/rustdesk*.desktop; do
  new="usr/share/applications/$(basename "$f" | sed 's/rustdesk/hagedesk/')"
  sed 's/rustdesk/hagedesk/g; s/RustDesk/HageDesk/g' "$f" > "$new"
  rm "$f"
done

# Icons: replace the RustDesk ones with the HageDesk PNGs (the window looks them up without SVG).
rm -f usr/share/icons/hicolor/*/apps/rustdesk.*
for size in 32 64 128 256; do
  case $size in
    256) png="$repo/res/128x128@2x.png" ;;
    *) png="$repo/res/${size}x${size}.png" ;;
  esac
  install -D -m 644 "$png" "usr/share/icons/hicolor/${size}x${size}/apps/hagedesk.png"
done

# Maintainer scripts.
for f in DEBIAN/preinst DEBIAN/postinst DEBIAN/prerm DEBIAN/postrm; do
  [ -f "$f" ] && sed -i 's/rustdesk/hagedesk/g; s/RustDesk/HageDesk/g' "$f"
done

# Package metadata: keep upstream's Maintainer as the original author.
sed -i \
  -e 's/^Package: rustdesk$/Package: hagedesk/' \
  -e 's|^Homepage: .*|Homepage: https://github.com/Pir4s/HageDesk|' \
  -e 's/^Description: .*/Description: HageDesk - acesso remoto da Hage (baseado no RustDesk)./' \
  DEBIAN/control

# Text files still pointing at rustdesk paths would break the install; flag them in the log.
if grep -rIl 'usr/share/rustdesk\|usr/bin/rustdesk\|rustdesk\.service' . ; then
  echo "::warning::rustdesk references left in the files listed above"
fi

cd "$work"
dpkg-deb --root-owner-group -b pkg "$out_deb"
dpkg-deb -I "$out_deb" | sed -n '/Package:/,/Description:/p'
dpkg-deb -c "$out_deb" | grep -E 'hagedesk(\.service|\.desktop|\.png)?$|/hagedesk/hagedesk$'
