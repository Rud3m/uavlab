#!/usr/bin/env bash
#
# cleanup-lab.sh — reset a lab machine by removing the files and mount points
# the exercises create, so the next student starts clean.
#
# It unmounts /mnt/p2../mnt/p4 (loop mounts of the SD-card partitions), detaches
# their loop devices, and deletes the artifacts the walkthrough generates:
#   *.raw dumps, squashfs-root/, the copied squashfs, 3DR-Solo.apk, opensolo.words,
#   wifite captures (hs/, *.cap, *.pcapng, cracked.txt), and mavproxy logs.
#
# It NEVER touches the tracked repo inputs (files/solo/…, files/opensolo.words,
# files/*.lua, images) or the installed tools (QGroundControl, the MAVProxy venv).
#
# Usage:
#   ./cleanup-lab.sh            # show what would be removed, then ask to confirm
#   ./cleanup-lab.sh -y         # remove without prompting
#   ./cleanup-lab.sh -n         # dry run — only list what would be removed
#   ./cleanup-lab.sh -h         # help
#   ./cleanup-lab.sh /path/repo # operate on a specific repo clone

set -u

# ── options ────────────────────────────────────────────────────────────────
ASSUME_YES=0
DRY_RUN=0
LAB_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)      ASSUME_YES=1 ;;
    -n|--dry-run)  DRY_RUN=1 ;;
    -h|--help)     awk 'NR>=3 { if ($0 !~ /^#/) exit; sub(/^# ?/,""); print }' "$0"; exit 0 ;;
    -*)            echo "Unknown option: $1" >&2; exit 2 ;;
    *)             LAB_DIR="$1" ;;
  esac
  shift
done

c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_red=$'\e[31m'; c_dim=$'\e[90m'; c_rst=$'\e[0m'
warn() { echo "${c_ylw}[!] $*${c_rst}"; }
info() { echo "${c_dim}    $*${c_rst}"; }

# ── resolve + validate the repo root ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "${LAB_DIR}" ] || LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAB_DIR="$(cd "${LAB_DIR}" 2>/dev/null && pwd || true)"

if [ -z "${LAB_DIR}" ] || [ "${LAB_DIR}" = "/" ]; then
  echo "${c_red}Refusing to run: invalid lab directory.${c_rst}" >&2; exit 1
fi
if [ ! -d "${LAB_DIR}/apps" ] || [ ! -d "${LAB_DIR}/lab" ]; then
  echo "${c_red}'${LAB_DIR}' does not look like the uavlab repo (no apps/ + lab/).${c_rst}" >&2
  echo "Pass the repo path explicitly, e.g.  ./cleanup-lab.sh ~/uavlab" >&2
  exit 1
fi

MOUNTS=(/mnt/p2 /mnt/p3 /mnt/p4)

# Top-level artifacts the exercises create (globs, relative to LAB_DIR).
FILE_PATTERNS=(
  '3dr-solo-uav-p'*.raw          # dd partition dumps
  '3dr-solo-imx6solo-3dr-1080p.squashfs'  # working copy (tracked one is in files/solo/)
  '3DR-Solo.apk' 'base.apk'      # adb pull
  'opensolo.words'               # cewl output (tracked one is in files/)
  '*.cap' '*.pcapng' 'cracked.txt' 'wifite.log'  # wifite
  'mav.tlog' 'mav.tlog.raw' 'mav.parm'           # mavproxy logs
)
DIR_TARGETS=( 'squashfs-root' 'hs' )   # unsquashfs output, wifite handshake dir

# ── collect what actually exists ───────────────────────────────────────────
is_mounted() { mountpoint -q "$1" 2>/dev/null || grep -qs " $1 " /proc/mounts; }

TO_UMOUNT=(); TO_RMDIR=(); TO_RM=()
for m in "${MOUNTS[@]}"; do
  if is_mounted "$m"; then TO_UMOUNT+=("$m"); fi
  if [ -d "$m" ]; then TO_RMDIR+=("$m"); fi
done

shopt -s nullglob
for pat in "${FILE_PATTERNS[@]}"; do
  for f in "${LAB_DIR}/"$pat; do [ -e "$f" ] && TO_RM+=("$f"); done
done
for d in "${DIR_TARGETS[@]}"; do
  [ -e "${LAB_DIR}/${d}" ] && TO_RM+=("${LAB_DIR}/${d}"); done
shopt -u nullglob

if [ ${#TO_UMOUNT[@]} -eq 0 ] && [ ${#TO_RMDIR[@]} -eq 0 ] && [ ${#TO_RM[@]} -eq 0 ]; then
  echo "${c_grn}Nothing to clean — the lab is already reset.${c_rst}"
  exit 0
fi

# ── report ─────────────────────────────────────────────────────────────────
echo "${c_grn}Lab cleanup for:${c_rst} ${LAB_DIR}"
[ ${#TO_UMOUNT[@]} -gt 0 ] && { echo "${c_ylw}Unmount:${c_rst}";  for m in "${TO_UMOUNT[@]}"; do echo "  $m"; done; }
[ ${#TO_RMDIR[@]}  -gt 0 ] && { echo "${c_ylw}Remove mount dirs:${c_rst}"; for m in "${TO_RMDIR[@]}"; do echo "  $m"; done; }
[ ${#TO_RM[@]}     -gt 0 ] && { echo "${c_ylw}Delete files:${c_rst}"; for f in "${TO_RM[@]}"; do echo "  $f"; done; }

if [ "${DRY_RUN}" -eq 1 ]; then
  echo "${c_dim}(dry run — nothing was changed)${c_rst}"
  exit 0
fi

if [ "${ASSUME_YES}" -ne 1 ]; then
  printf "%s" "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# ── execute ────────────────────────────────────────────────────────────────
# 1) unmount partitions (lazy fallback if busy)
for m in "${TO_UMOUNT[@]}"; do
  if sudo umount "$m" 2>/dev/null; then info "unmounted $m"
  elif sudo umount -l "$m" 2>/dev/null; then warn "$m was busy — lazy-unmounted"
  else warn "could not unmount $m (close anything using it and re-run)"; fi
done

# 2) detach any loop devices still bound to the raw dumps
for f in "${TO_RM[@]}"; do
  case "$f" in
    *.raw)
      for dev in $(sudo losetup -j "$f" 2>/dev/null | cut -d: -f1); do
        sudo losetup -d "$dev" 2>/dev/null && info "detached $dev"
      done ;;
  esac
done

# 3) remove mount-point directories (only if now empty)
for m in "${TO_RMDIR[@]}"; do
  if is_mounted "$m"; then warn "leaving $m (still mounted)"; continue; fi
  sudo rmdir "$m" 2>/dev/null && info "removed $m" || warn "left $m (not empty)"
done

# 4) delete lab artifacts
for f in "${TO_RM[@]}"; do
  sudo rm -rf -- "$f" && info "deleted $f"
done

echo "${c_grn}Cleanup complete.${c_rst}"
