#!/usr/bin/env bash
#
# Launch QGroundControl. Finds the AppImage whether this script is run from the
# apps/ dir or from apps/QGroundControl/. Tries a normal FUSE launch first; if
# libfuse.so.2 is missing (newer Kali/Debian), extracts and runs the AppImage.
DIR="$(cd "$(dirname "$0")" && pwd)"

# Locate the AppImage: beside this script, in a QGroundControl subdir, or search.
APPIMAGE=""
for cand in \
  "${DIR}/QGroundControl.AppImage" \
  "${DIR}/QGroundControl/QGroundControl.AppImage"; do
  [ -f "${cand}" ] && APPIMAGE="${cand}" && break
done
if [ -z "${APPIMAGE}" ]; then
  APPIMAGE="$(find "${DIR}" -maxdepth 2 -name 'QGroundControl*.AppImage' -print -quit 2>/dev/null)"
fi
if [ -z "${APPIMAGE}" ] || [ ! -f "${APPIMAGE}" ]; then
  echo "[runQGC] QGroundControl AppImage not found under ${DIR}"
  echo "[runQGC] Run the installer, or place QGroundControl.AppImage in ${DIR}/QGroundControl/"
  exit 1
fi

cd "$(dirname "${APPIMAGE}")"
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
