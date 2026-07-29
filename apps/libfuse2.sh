git clone https://github.com/libfuse/libfuse
cd libfuse
sudo apt -y install gettext
sudo apt -y install libtool
export ACLOCAL_PATH=/usr/share/aclocal
git checkout fuse_2_5_bugfix
./makeconf.sh
./configure --disable-kernel-module
make
sudo make install
cd ..
#sudo rm /etc/mtab
#sudo touch /etc/mtab
#sudo chmod 777 /etc/mtab
#./QGroundControl.AppImage --appimage-extract
