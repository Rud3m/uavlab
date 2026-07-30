#!/usr/bin/env bash
#
# Build libfuse 2.x from source to provide libfuse.so.2, which AppImages
# (e.g. QGroundControl) need but which newer Kali/Debian no longer package.
# Called automatically by install-lab-tools.sh when apt has no libfuse2.
set -e

if ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
  echo "libfuse.so.2 already present — nothing to build."
  exit 0
fi

echo "--- Installing build dependencies for libfuse ---"
sudo apt-get install -y git gettext libtool autoconf automake pkg-config make gcc

# Clone once; reuse the tree on re-runs.
if [ ! -d libfuse ]; then
  git clone https://github.com/libfuse/libfuse
fi
cd libfuse

export ACLOCAL_PATH=/usr/share/aclocal
git checkout fuse_2_5_bugfix
./makeconf.sh
./configure --disable-kernel-module
make
sudo make install
sudo ldconfig
cd ..

echo "--- libfuse2 built and installed (libfuse.so.2) ---"
