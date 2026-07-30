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
# Local apps (QGroundControl, MAVProxy venv) install alongside these scripts,
# inside the repo's apps/ dir — so everything stays self-contained in the clone.
APP_DIR="${SCRIPT_DIR}"
PLUGIN_DIR="${TARGET_HOME}/.local/lib/wireshark/plugins"

# QGroundControl AppImage source. Set QGC_URL=... to force a specific URL;
# otherwise the candidates below are tried in order (latest GitHub release first).
QGC_URL="${QGC_URL:-}"
QGC_CANDIDATES=(
  "https://github.com/mavlink/qgroundcontrol/releases/latest/download/QGroundControl.AppImage"
  "https://github.com/mavlink/qgroundcontrol/releases/latest/download/QGroundControl-x86_64.AppImage"
  "https://github.com/mavlink/qgroundcontrol/releases/download/v4.0.1/QGroundControl.AppImage"
)

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
  section "MAVProxy (isolated virtualenv)"
  local vdir="${APP_DIR}/mavproxy"
  local venv="${vdir}/mavproxy_venv"

  # venv tooling + headers some deps may need
  apt_install python3-venv python3-dev >/dev/null 2>&1 || true
  apt_install libxml2-dev libxslt1-dev >/dev/null 2>&1 || true

  mkdir -p "${vdir}"
  python3 -m venv "${venv}" || { warn "could not create venv"; return 1; }
  "${venv}/bin/pip" install --upgrade pip wheel setuptools >/dev/null 2>&1 || true
  # 'future' is the dep that was missing from the broken ~/.local install.
  "${venv}/bin/pip" install --no-cache-dir MAVProxy future pymavlink pyserial \
    || { warn "pip install into venv failed"; return 1; }

  # Remove the broken user-local install so it can't shadow our wrappers.
  rm -f "${TARGET_HOME}/.local/bin/mavproxy" "${TARGET_HOME}/.local/bin/mavproxy.py" 2>/dev/null || true

  # Global wrappers so `mavproxy`, `mavproxy.py`, and `sudo mavproxy` all
  # transparently run inside the venv — students never touch it.
  local target
  for target in mavproxy mavproxy.py; do
    sudo tee "/usr/local/bin/${target}" >/dev/null <<EOF
#!/usr/bin/env bash
# Auto-generated by install-lab-tools.sh — runs MAVProxy from its own venv.
exec "${venv}/bin/mavproxy.py" "\$@"
EOF
    sudo chmod +x "/usr/local/bin/${target}"
  done
  note "MAVProxy runs from ${venv} via /usr/local/bin/mavproxy[.py]"
}

# Ensure libfuse.so.2 exists (AppImages need it). Try apt, then source-build.
ensure_libfuse2() {
  if ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    note "libfuse.so.2 already present."
    return 0
  fi
  # Package name changed with the time_t transition; try both.
  if apt_install libfuse2t64 || apt_install libfuse2; then
    note "libfuse2 installed via apt."
    return 0
  fi
  warn "libfuse2 not in apt — building it from source via libfuse2.sh …"
  if [ ! -f "${SCRIPT_DIR}/libfuse2.sh" ]; then
    warn "libfuse2.sh not found next to this script."
    return 1
  fi
  local bdir="${APP_DIR}/QGroundControl/build-libfuse"
  mkdir -p "${bdir}"
  ( cd "${bdir}" && bash "${SCRIPT_DIR}/libfuse2.sh" )
}

install_qgroundcontrol() {
  section "QGroundControl"
  # Runtime libraries the AppImage needs.
  apt_install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl \
              python3-gi python3-gst-1.0 \
              libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor0 \
    || warn "Some QGC runtime libs failed to install"

  local have_fuse=1
  ensure_libfuse2 || { have_fuse=0; warn "libfuse2 unavailable — runQGC.sh will fall back to --appimage-extract-and-run"; }

  local qgc_dir="${APP_DIR}/QGroundControl"
  mkdir -p "${qgc_dir}"
  [ -f "${SCRIPT_DIR}/runQGC.sh" ]   && cp "${SCRIPT_DIR}/runQGC.sh"   "${qgc_dir}/" && chmod +x "${qgc_dir}/runQGC.sh"
  [ -f "${SCRIPT_DIR}/libfuse2.sh" ] && cp "${SCRIPT_DIR}/libfuse2.sh" "${qgc_dir}/" && chmod +x "${qgc_dir}/libfuse2.sh"

  local appimage="${qgc_dir}/QGroundControl.AppImage"
  if [ -f "${appimage}" ] && [ "$(stat -c%s "${appimage}" 2>/dev/null || echo 0)" -gt 1000000 ]; then
    note "AppImage already present — skipping download."
  else
    local urls=()
    [ -n "${QGC_URL}" ] && urls+=("${QGC_URL}")
    urls+=("${QGC_CANDIDATES[@]}")
    local got=0
    for url in "${urls[@]}"; do
      note "Trying ${url}"
      if curl -fSL "${url}" -o "${appimage}" \
           && [ "$(stat -c%s "${appimage}" 2>/dev/null || echo 0)" -gt 1000000 ]; then
        got=1; note "Downloaded QGroundControl AppImage."; break
      fi
      rm -f "${appimage}"
    done
    if [ "${got}" -eq 0 ]; then
      warn "All QGC download URLs failed. Pre-stage QGroundControl.AppImage into ${qgc_dir}/"
      warn "(or set QGC_URL=<url> and re-run)."
      return 1
    fi
  fi
  chmod +x "${appimage}"
  note "Launch it later with:  cd ${qgc_dir} && ./runQGC.sh"
  [ "${have_fuse}" -eq 0 ] && return 0  # installed, just needs extract-and-run to launch
  return 0
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
