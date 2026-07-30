#!/usr/bin/env bash
#
# Launch QGroundControl. Finds the AppImage whether this script is run from the
# apps/ dir or from apps/QGroundControl/.
#
# By default it runs with --appimage-extract-and-run, which does NOT need FUSE
# or a working /etc/mtab (both are commonly broken on Kali and produce
# "fusermount: failed to open /etc/mtab: Invalid argument"). It extracts to a
# temp dir and runs from there — a few seconds slower to start, but reliable.
#
# To use the faster FUSE mount instead (needs libfuse.so.2 + a sane /etc/mtab):
#     QGC_USE_FUSE=1 ./runQGC.sh
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

if [ "${QGC_USE_FUSE:-0}" = "1" ]; then
  # Fast path: FUSE mount. Repair /etc/mtab first (fusermount needs a real,
  # writable file; a symlink to /proc/self/mounts breaks some builds).
  if [ ! -f /etc/mtab ] || [ -L /etc/mtab ]; then
    sudo rm -f /etc/mtab 2>/dev/null || true
    sudo touch /etc/mtab 2>/dev/null || true
    sudo chmod 666 /etc/mtab 2>/dev/null || true
  fi
  exec "${APPIMAGE}" "$@"
fi

# Default path: no FUSE, no /etc/mtab needed.
exec "${APPIMAGE}" --appimage-extract-and-run "$@"
