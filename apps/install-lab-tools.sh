#!/usr/bin/env bash
#
# install-lab-tools.sh — one-shot installer for the UAV Security Workshop lab.
#
# Installs every tool used by lab/lab.md:
#   squashfs-tools, openssh-client-ssh1, adb, jadx, QGroundControl,
#   cewl, wifite (+ deps), Wireshark + MAVLink plugin, MAVProxy.
#
# Run as your normal Kali user (NOT root) — the script calls sudo itself and
# installs the Wireshark plugin + QGroundControl into your home directory:
#
#     cd apps
#     chmod +x install-lab-tools.sh
#     ./install-lab-tools.sh
#
# It is safe to re-run: anything already present is skipped, and a summary of
# what succeeded / needs attention is printed at the end.
#
# This is the trimmed, lab-focused sibling of install-workshop-apps.sh (which
# provisions the full Dark Wolf workshop). Build off whichever you need.

VERSION="20260729"

# ── Paths & target user ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FILES_DIR="${REPO_ROOT}/files"

# Whether launched normally or via sudo, resolve the real (non-root) user.
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(eval echo "~${TARGET_USER}")"
APP_DIR="${TARGET_HOME}/apps"
PLUGIN_DIR="${TARGET_HOME}/.local/lib/wireshark/plugins"

# QGroundControl AppImage source (override with QGC_URL=... ./install-lab-tools.sh)
QGC_URL="${QGC_URL:-https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl.AppImage}"

export DEBIAN_FRONTEND=noninteractive

# ── Pretty output + result tracking ────────────────────────────────────────
c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_red=$'\e[31m'; c_dim=$'\e[90m'; c_rst=$'\e[0m'
declare -a RESULT_OK RESULT_FAIL
section() { echo; echo "${c_grn}── $* ────────────────────────────────────${c_rst}"; }
note()    { echo "${c_dim}    $*${c_rst}"; }
warn()    { echo "${c_ylw}[!] $*${c_rst}"; }

# apt install that tolerates one failed package name, returns nonzero on failure
apt_install() { sudo apt-get install -y "$@"; }

if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER}" ]; then
  warn "Running as root directly. Prefer running as your normal 'kali' user;"
  warn "the Wireshark plugin and QGroundControl will be placed under ${TARGET_HOME}."
fi

echo "${c_grn}UAV Security Workshop — lab tool installer (v${VERSION})${c_rst}"
echo "User: ${TARGET_USER}    Home: ${TARGET_HOME}"
echo "Repo: ${REPO_ROOT}"

section "Refreshing package lists"
sudo apt-get update || warn "apt update reported problems — continuing anyway"

# ── Per-tool installers ────────────────────────────────────────────────────

install_squashfs() {
  section "squashfs-tools"
  apt_install squashfs-tools
}

install_ssh1() {
  section "openssh-client-ssh1"
  apt_install openssh-client-ssh1 && return 0
  warn "openssh-client-ssh1 not in repos — trying 'ssh1'"
  apt_install ssh1
}

install_adb() {
  section "adb (Android Debug Bridge)"
  apt_install adb
}

install_jadx() {
  section "jadx / jadx-gui"
  apt_install default-jdk || warn "default-jdk failed; jadx-gui needs Java 11+"
  apt_install jadx
}

install_cewl() {
  section "cewl"
  apt_install cewl
}

install_wifite() {
  section "wifite (+ aircrack-ng, tshark, hcxdumptool, hcxtools)"
  # tshark/wireshark ask about non-root capture; preseed the answer.
  echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
  apt_install wifite aircrack-ng tshark hcxdumptool hcxtools
}

install_wireshark() {
  section "Wireshark + MAVLink plugin"
  echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
  apt_install wireshark || return 1
  sudo usermod -aG wireshark "${TARGET_USER}" \
    && note "Added ${TARGET_USER} to the 'wireshark' group (re-login required)."
  mkdir -p "${PLUGIN_DIR}"
  local copied=0
  for lua in mavlink_2_common.lua bit32.lua; do
    if [ -f "${FILES_DIR}/${lua}" ]; then
      cp "${FILES_DIR}/${lua}" "${PLUGIN_DIR}/" && copied=1
    fi
  done
  [ "${copied}" -eq 1 ] && note "MAVLink dissector copied to ${PLUGIN_DIR}" \
                        || warn "MAVLink .lua files not found in ${FILES_DIR}"
}

install_mavproxy() {
  section "MAVProxy"
  apt_install mavproxy && return 0
  warn "mavproxy not available via apt — installing via pip"
  pip3 install --break-system-packages MAVProxy
}

install_qgroundcontrol() {
  section "QGroundControl"
  # Runtime libraries the AppImage needs.
  apt_install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl \
              python3-gi python3-gst-1.0 \
              libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor0 \
    || warn "Some QGC runtime libs failed to install"
  # libfuse2 name changed with the time_t transition; try both.
  apt_install libfuse2t64 || apt_install libfuse2 \
    || warn "libfuse2 not found. If the AppImage won't start, run ${SCRIPT_DIR}/libfuse2.sh"

  local qgc_dir="${APP_DIR}/QGroundControl"
  mkdir -p "${qgc_dir}"
  [ -f "${SCRIPT_DIR}/runQGC.sh" ] && cp "${SCRIPT_DIR}/runQGC.sh" "${qgc_dir}/" && chmod +x "${qgc_dir}/runQGC.sh"
  [ -f "${SCRIPT_DIR}/libfuse2.sh" ] && cp "${SCRIPT_DIR}/libfuse2.sh" "${qgc_dir}/" && chmod +x "${qgc_dir}/libfuse2.sh"

  local appimage="${qgc_dir}/QGroundControl.AppImage"
  if [ -f "${appimage}" ]; then
    note "AppImage already present — skipping download."
  else
    note "Downloading QGroundControl AppImage…"
    curl -fL "${QGC_URL}" -o "${appimage}" \
      || { warn "Download failed. Pre-stage QGroundControl.AppImage into ${qgc_dir}/"; return 1; }
  fi
  chmod +x "${appimage}"
  note "Launch it later with:  cd ${qgc_dir} && ./runQGC.sh"
}

# ── Run everything, record pass/fail ───────────────────────────────────────
run() {
  local name="$1"; shift
  if "$@"; then RESULT_OK+=("${name}"); else RESULT_FAIL+=("${name}"); fi
}

run "squashfs-tools"        install_squashfs
run "openssh-client-ssh1"   install_ssh1
run "adb"                   install_adb
run "jadx"                  install_jadx
run "cewl"                  install_cewl
run "wifite"                install_wifite
run "wireshark + plugin"    install_wireshark
run "mavproxy"              install_mavproxy
run "QGroundControl"        install_qgroundcontrol

# Fix ownership if any home-dir files were created as root.
if [ -d "${APP_DIR}" ]; then
  sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${APP_DIR}" 2>/dev/null || true
fi
if [ -d "${PLUGIN_DIR}" ]; then
  sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local" 2>/dev/null || true
fi

section "Cleanup"
sudo apt-get autoremove -y >/dev/null 2>&1 || true

# ── Summary ────────────────────────────────────────────────────────────────
echo
echo "${c_grn}══════════════════ Installation summary ══════════════════${c_rst}"
for t in "${RESULT_OK[@]}";   do echo "  ${c_grn}✔${c_rst} ${t}"; done
for t in "${RESULT_FAIL[@]}"; do echo "  ${c_red}x${c_rst} ${t}  (needs attention)"; done
echo
if [ "${#RESULT_FAIL[@]}" -eq 0 ]; then
  echo "${c_grn}All lab tools installed.${c_rst}"
else
  warn "${#RESULT_FAIL[@]} item(s) need attention — see the notes above."
fi
echo "${c_ylw}Log out and back in (or reboot) so Wireshark capture permissions take effect.${c_rst}"
