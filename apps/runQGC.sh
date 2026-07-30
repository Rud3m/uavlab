#!/usr/bin/env bash
#
# Launch QGroundControl. Tries a normal FUSE launch first; if libfuse.so.2 is
# missing (newer Kali/Debian), falls back to extracting and running the AppImage.
cd "$(dirname "$0")"

APPIMAGE="./QGroundControl.AppImage"
chmod +x "${APPIMAGE}" 2>/dev/null

# Some AppImages need a writable /etc/mtab for FUSE mounting.
if [ ! -e /etc/mtab ]; then
  sudo ln -sf /proc/self/mounts /etc/mtab 2>/dev/null || true
fi

if ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
  exec "${APPIMAGE}" "$@"
else
  echo "[runQGC] libfuse.so.2 not found — launching with --appimage-extract-and-run"
  exec "${APPIMAGE}" --appimage-extract-and-run "$@"
fi
