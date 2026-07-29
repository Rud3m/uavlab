#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "version 20260725-1608"


# TODO: mavlink wireshark plugin

INSTALL_USER="kali"
INSTALL_GROUP="${INSTALL_USER}"
HOME_DIR="/home/${INSTALL_USER}"
APP_DIR="${HOME_DIR}/workshop/apps"
echo "Starting app installation for Dark Wolf workshop for user ${USER} on Kali Rolling 2026.2 and similar"

echo "--- Updating and upgrading system packages ---"
sudo apt update
sudo apt upgrade -y
#sudo apt dist-upgrade -y


sudo TERM=dumb DEBIAN_FRONTEND=noninteractive apt -y install mono-devel
sudo TERM=dumb DEBIAN_FRONTEND=noninteractive apt -y install mono-libraries-debug



# --- Install essential development tools ---
echo "--- Installing Git, Python tools dependencies, OpenJDK ---"
sudo apt install -y git
#sudo apt install -y python3 python3-pip python3-venv openjdk-17-jdk curl unzip pipenv
sudo apt install -y python3 python3-pip python3-venv openjdk-21-jdk curl unzip pipenv

# --- Install flatpack ---
echo "--- Installing additional wifi tools ---"
sudo apt install hcxdumptool hcxtools

# --- Install snapd ---
echo "--- Installing and starting snapd ---"
sudo apt install -y snapd
sudo systemctl enable snapd
sudo systemctl start snapd

# --- Install flatpack ---
echo "--- Installing flatpack ---"
sudo apt install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo


# --- Apps Directory ---
echo "--- Creating apps directory ---"
if [ ! -d "$APP_DIR" ]; then
  # Directory does not exist, so create it
  echo "Creating ${APP_DIR}"
  mkdir -p "${APP_DIR}"
fi
echo "Local apps are installed into ${APP_DIR}"

# --- Install Wireshark ---
install_wireshark() {
    echo "--- Installing Wireshark ---"
    echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
    DEBIAN_FRONTEND=noninteractive sudo apt install -y wireshark
    # Allow non-root users (like 'vagrant') to capture packets
    # sudo dpkg-reconfigure wireshark-common # Select 'Yes' when prompted
    sudo usermod -aG wireshark ${INSTALL_USER}
    # Note: The 'vagrant' user will need to log out and back in for group changes to take effect.
    mkdir -p /home/kali/.local/lib/wireshark/plugins
    cp ../files/bit32.lua /home/kali/.local/lib/wireshark/plugins
    cp ../files/mavlink_2_common.lua /home/kali/.local/lib/wireshark/plugins
    
} 

# --- Install JADX-GUI ---
install_jadx() {
    echo "--- Installing JADX-GUI ---"
    #JADX_VERSION="1.4.7" # Check https://github.com/skylot/jadx/releases for the latest version
    #JADX_URL="https://github.com/skylot/jadx/releases/download/v${JADX_VERSION}/jadx-${JADX_VERSION}.zip"
    #JADX_INSTALL_DIR="${APP_DIR}/jadx"

    #echo "Downloading JADX-GUI v${JADX_VERSION} from ${JADX_URL}..."
    #curl -LO "${JADX_URL}"
    #mkdir -p "${JADX_INSTALL_DIR}"
    #sudo unzip "jadx-${JADX_VERSION}.zip" -d "${JADX_INSTALL_DIR}"
    #rm "jadx-${JADX_VERSION}.zip"

    # Create a symlink for easy access from /usr/local/bin
    #if [ ! -L "/usr/local/bin/jadx-gui" ]; then
      # Directory does not exist, so create it
      #sudo ln -s "${JADX_INSTALL_DIR}/jadx-${JADX_VERSION}/bin/jadx-gui" /usr/local/bin/jadx-gui
    #fi
    sudo apt -y install jadx
    echo "JADX-GUI installed. Run 'jadx-gui' from the terminal."
}

# --- Install QGroundControl ---
install_qgroundcontrol() {
    echo "--- Installing QGroundControl ---"
    QGC_VERSION="v4.0.1" # Check https://github.com/skylot/jadx/releases for the latest version
    # App name varies by version
    #QGC_APP="QGroundControl-x86_64.AppImage" 
    QGC_APP="QGroundControl.AppImage" 
    QGC_URL="https://github.com/mavlink/qgroundcontrol/releases/download/${QGC_VERSION}/${QGC_APP}"
    QGC_DIR="${APP_DIR}/QGroundControl"
    mkdir -p ${QGC_DIR}
    mv runQGC.sh ${QGC_DIR} 
    chmod +x ${QGC_DIR}/runQGC.sh
    mv libfuse2.sh ${QGC_DIR} 
    chmod +x ${QGC_DIR}/libfuse2.sh
    cd ${QGC_DIR}
    sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl -y
    sudo apt install python3-gi python3-gst-1.0 -y
    #sudo apt install libfuse2 -y
    sudo apt install libfuse3-4 -y
    sudo apt install libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor-dev -y
    sudo ./libfuse2.sh
    cd ${QGC_DIR}

    echo "Downloading ${QGC_APP}  v${QGC_VERSION} from ${QGC_URL}..."
    sudo curl -LO "${QGC_URL}"
    if [ ! -f QGroundControl.AppImage ]; then
        sudo mv ${QGC_APP} QGroundControl.AppImage
    fi
    sudo chmod +x ${QGC_DIR}/QGroundControl.AppImage
    sudo chmod +x ${QGC_DIR}/runQGC.sh
}

# --- Install OpenDroneID ---
install_opendroneid() {
    echo "--- Installing OpenDroneID ---"
    ODID_DIR="${APP_DIR}/OpenDroneID"
    if [ ! -d "${ODID_DIR}" ]; then
       mkdir -p "${ODID_DIR}"
       sudo git clone https://github.com/opendroneid/wireshark-dissector ${ODID_DIR}
    fi
}

# --- Install ADB ---
install_adb() {
    echo "--- Installing adb ---"
    sudo apt -y install adb
}

# --- Install SDRangel ---
install_sdrangel() {
    echo "--- Installing sdrangel ---"
    sudo snap install sdrangel
    sudo snap connect sdrangel:raw-usb
    sudo snap connect sdrangel:audio-record
    sudo systemctl enable --now snapd.socket
    sudo systemctl enable --now snapd.apparmor
    sudo snap refresh
    # sudo snap warnings
}


# --- Install MissionPlanner ---
install_missionplanner() {
    echo "--- Installing MissionPlanner  ---"
    MP_DIR="${APP_DIR}/MissionPlanner"
    MP_URL="https://firmware.ardupilot.org/Tools/MissionPlanner/MissionPlanner-latest.zip"
    if [ ! -d "${MP_DIR}" ]; then
        mkdir -p "${MP_DIR}"
        cd ${MP_DIR}
        sudo TERM=dumb certmgr -ssl https://autotest.ardupilot.org/LogMessages/Copter/LogMessages.xml.xz
        wget http://ftp.us.debian.org/debian/pool/main/m/mono/ca-certificates-mono_6.12.0.199+dfsg-6_all.deb
        sudo dpkg -i ca-certificates-mono_6.12.0.199+dfsg-6_all.deb
        wget ${MP_URL}
        unzip MissionPlanner-latest.zip
    fi
}

# --- Install MissionPlanner ---
install_nrfutil() {
    echo "--- Installing NRFUtil ---"
    NRF_DIR="${APP_DIR}/nrfutil"
    NRF_URL="https://files.nordicsemi.com/ui/api/v1/download?repoKey=swtools&path=external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil&isNativeBrowsing=false"
    NRF_UDEV="https://raw.githubusercontent.com/NordicSemiconductor/nrf-udev/refs/heads/main/nrf-udev_1.0.1-all/lib/udev/rules.d/71-nrf.rules"
    if [ ! -d "${NRF_DIR}" ]; then
        mkdir -p "${NRF_DIR}"
        cd ${NRF_DIR}
	wget ${NRF_URL} -O nrfutil
	cp nrfutil /home/kali/.local/bin
	chown kali:kali /home/kali/.local/bin
	chmod +x /home/kali/.local/bin/nrfutil
	wget ${NRF_UDEV} -O 71-nrf.rules
	sudo cp 71-nrf.rules /etc/udev/rules.d
	sudo udevadm trigger
    fi
}


# --- Setup Python applications in individual virtual environments ---

# Set venvs ownership to vagrant
sudo chown -R ${INSTALL_USER}:${INSTALL_GROUP} ${APP_DIR}

# Function to setup a Python application in its own venv
setup_python_app_venv() {
    local app_name=$1
    local pip_packages=$2
    local venv_path="${APP_DIR}/${app_name}/${app_name}_venv"
    local bin_dir="${venv_path}/bin"

    # Create venv and activate it
    python3 -m venv "${venv_path}"
    source "${bin_dir}/activate"
    
    # Install packages
    echo "Installing ${pip_packages} into ${app_name}_venv..."
    pip install --no-cache-dir ${pip_packages}
    
    # Deactivate venv
    deactivate

    # Add the venv's bin directory to the vagrant user's PATH
    # This makes commands like 'frida', 'sikw00f', etc. directly executable
    echo "Adding ${bin_dir} to users PATH in .bashrc"
    echo "export PATH=\"${bin_dir}:\$PATH\"" | sudo tee -a ${USER_HOME}/.bashrc > /dev/null
    sudo chown ${INSTALL_USER}:${INSTALL_GROUP} ${USER_HOME}/.bashrc # Ensure vagrant owns their .bashrc

    echo "${app_name} installed in its virtual environment. Will be available after re-logging in or sourcing .bashrc."
}

# Install Frida
install_frida() {
    setup_python_app_venv "frida" "frida-tools==14.8.1"
    cd /home/kali/workshop/apps/frida
    git clone https://github.com/rootbsd/fridump3
}


# Install Sikw00f
install_sikw00f() {
    # create directory, install from git below
    setup_python_app_venv "sikw00f" "pymavlink==2.4.42"

    # git install Sikw00f
    cd ${APP_DIR}/sikw00f
    source sikw00f_venv/bin/activate
    git clone https://github.com/nicholasaleks/sikw00f
    cd sikw00f
    pipenv requirements > requirements.txt
    python3 -m pip install -r requirements.txt
    deactivate
    chmod +x sikw00f.py
}

# Install MAVProxy
# MAVProxy might have specific dependencies or a different executable name.
# It's usually `mavproxy.py` from the installed package. The `setup_python_app_venv`
# puts the bin dir in PATH, so it should be found.
install_mavproxy() {
    setup_python_app_venv "mavproxy" "MAVProxy"
}

# Set ownership to user 
sudo chown -R ${INSTALL_USER}:${INSTALL_GROUP} ${APP_DIR}

# --- Final Cleanup ---
echo "--- Performing final cleanup ---"
sudo apt autoremove -y
sudo apt clean

echo "Installation complete!"
echo "---------------------------------------------------------"
#echo "Post-installation notes:"
#echo "- For Wireshark group changes to take effect, you must log out of the GUI/SSH and log back in."
#echo "- For Python tools to be directly in your PATH, you might need to 'source ~/.bashrc' or log out/in."
#echo "  Example: kali@kali:~$ source ~/.bashrc"
#echo "  Then try: frida --version, sikw00f --help, mavproxy.py --help, nrfutil --version"
#echo "- JADX-GUI can be launched by typing 'jadx-gui' in a terminal."

install_wireshark
install_jadx
install_qgroundcontrol
install_opendroneid
install_adb
install_sdrangel
install_missionplanner
install_nrfutil
install_frida
install_sikw00f
install_mavproxy


# require uses input
#flatpak install flathub com.obsproject.Studio
# run
#flatpak run com.obsproject.Studio

sudo chown -R kali:kali ${APP_DIR}
