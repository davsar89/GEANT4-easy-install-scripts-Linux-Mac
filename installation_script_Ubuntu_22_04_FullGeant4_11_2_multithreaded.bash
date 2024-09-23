#!/bin/bash
set -e

# Main directory setup
mkdir -p geant4
cd geant4

base_dir="${PWD}"
CMake_path="${base_dir}/cmake/bin/cmake"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Function to install dependencies
install_dependencies() {
    echo "Some missing dependencies were detected."
    read -p "Do you have (root) sudo access? [Y/n]: " answer
    answer=${answer:-Y}
    if [[ $answer =~ [Nn] ]]; then
        echo "Root access is required to install missing dependencies. Aborting."
        exit 1
    fi

    read -p "Do you want to install missing dependencies? [Y/n]: " answer
    answer=${answer:-Y}
    if [[ $answer =~ [Yy] ]]; then
        sudo apt-get install "${ubuntu_dependencies[@]}"
    else
        echo "Missing dependencies are required for proper compilation and installation. Aborting."
        exit 0
    fi
}

# Function to set environment variables
set_environment() {
    if grep -Fxq "$1" ~/.bashrc; then
        echo -e "${GREEN}< source $1 > already set up in ~/.bashrc.${NC}"
    else
        echo "    " >> ~/.bashrc
        echo "$1" >> ~/.bashrc
        echo "______"
        echo -e "${GREEN}Added ${RED}$1${GREEN} to ${RED}~/.bashrc${GREEN} file.${NC}"
    fi
}

# Version and URL variables
g4_version="11.2.2"
g4_patch="p02"
g4_full_version="${g4_version/./_}.${g4_patch}"
folder_g4_version="Geant4-${g4_version}"
g4_url="https://github.com/Geant4/geant4/archive/refs/tags/v${g4_version}.tar.gz"
g4_arc="geant4.${g4_full_version}.tar.gz"

cmake_version="3.26.4"  # This is a recent stable version as of 2023
cmake_download_url="https://github.com/Kitware/CMake/releases/download/v${cmake_version}/cmake-${cmake_version}-linux-x86_64.tar.gz"

xerces_version="3.2.2"
xerces_w_ver="xerces-c-${xerces_version}"
xerces_arc="${xerces_w_ver}.tar.gz"
xerces_url="https://github.com/apache/xerces-c/archive/refs/tags/v${xerces_version}.tar.gz"

# Directory setup
src_dir="${base_dir}/source_geant4.${g4_full_version}/"
build_dir="${base_dir}/geant4_build_${g4_full_version}/"
install_dir="${base_dir}/geant4_install_${g4_full_version}/"
geant4_lib_dir="${install_dir}/lib/${folder_g4_version}/"

xercesc_build_dir="${base_dir}/build_xercesc_g4_${g4_full_version}/"
xercesc_install_dir="${base_dir}/install_xercesc_g4_${g4_full_version}/"
xercesc_inc_dir="${xercesc_install_dir}/include"
xercesc_lib_dir="${xercesc_install_dir}/lib64/libxerces-c-${xerces_version}.so"

# Create necessary directories
mkdir -p "${build_dir}" "${src_dir}" "${install_dir}" "${xercesc_build_dir}" "${xercesc_install_dir}"

# Check if OS is Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
fi

if [ ! "$OS" = "Ubuntu" ]; then
    echo "Error: OS is not Ubuntu. Script works only for Ubuntu. Aborting."
    exit 1
fi

# Define Ubuntu dependencies
ubuntu_dependencies=(
    "build-essential" "qtcreator" "qtbase5-dev" "cmake-qt-gui" "gcc" "g++" "gfortran"
    "zlib1g-dev" "libxerces-c-dev" "libx11-dev" "libexpat1-dev" "libxmu-dev"
    "libmotif-dev" "libboost-filesystem-dev" "libeigen3-dev" "libuuid1" "uuid-dev" "uuid-runtime"
    "libexpat1-dev"
)

# Check and install dependencies
dpkg -s "${ubuntu_dependencies[@]}" >/dev/null 2>&1 || install_dependencies

# Download and install CMake
rm -rf cmake
wget "${cmake_download_url}"
tar zxf cmake-${cmake_version}-linux-x86_64.tar.gz
mv cmake-${cmake_version}-linux-x86_64 cmake
rm -rf cmake-${cmake_version}-linux-x86_64.tar.gz

cd "${base_dir}"

# Install Xerces-C
wget "${xerces_url}"
mv v${xerces_version}.tar.gz "${xerces_arc}"
tar zxf "${xerces_arc}"
rm -rf "${xerces_arc}"

cd "${xercesc_build_dir}"
"${CMake_path}" \
    -DCMAKE_INSTALL_PREFIX="${xercesc_install_dir}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    "${base_dir}/${xerces_w_ver}"

make -j$(nproc)
make install

# Install Geant4
cd "${base_dir}"
wget "${g4_url}"
mv v${g4_version}.tar.gz "${g4_arc}"
tar zxf "${g4_arc}"
rm -rf "${g4_arc}"

cd "${build_dir}"
"${CMake_path}" \
    -DCMAKE_PREFIX_PATH="${xercesc_install_dir}" \
    -DCMAKE_INSTALL_PREFIX="${install_dir}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGEANT4_BUILD_MULTITHREADED=ON \
    -DGEANT4_INSTALL_DATA=ON \
    -DGEANT4_USE_GDML=ON \
    -DGEANT4_USE_G3TOG4=ON \
    -DGEANT4_USE_QT=ON \
    -DGEANT4_FORCE_QT4=OFF \
    -DGEANT4_USE_XM=ON \
    -DGEANT4_USE_OPENGL_X11=ON \
    -DGEANT4_USE_INVENTOR=OFF \
    -DGEANT4_USE_RAYTRACER_X11=ON \
    -DGEANT4_USE_SYSTEM_CLHEP=OFF \
    -DGEANT4_USE_SYSTEM_EXPAT=ON \
    -DGEANT4_USE_SYSTEM_ZLIB=OFF \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DXERCESC_INCLUDE_DIR="${xercesc_inc_dir}" \
    -DXERCESC_LIBRARY="${xercesc_lib_dir}" \
    "../geant4-${g4_version}/"

make -j$(nproc)
make install

# Set up environment variables
cd "${base_dir}"

# Remove old environment setup if exists
sed -i.bak '/## --> Added by Geant4 installation script/,/## <-- Added by Geant4 installation script/d' ~/.bashrc

# Add new environment setup
echo "## --> Added by Geant4 installation script" >> ~/.bashrc

set_environment "source ${install_dir}/bin/geant4.sh"
set_environment "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:${xercesc_install_dir}/include/"
set_environment "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:${xercesc_install_dir}/include/"
set_environment "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:${xercesc_install_dir}/lib64/"
set_environment "export LIBRARY_PATH=\$LIBRARY_PATH:${xercesc_install_dir}/lib64/"
set_environment "export PATH=\$PATH:${xercesc_install_dir}/include/"

GEANT4_DATA_DIR=${install_dir}/share/Geant4/data

set_environment "export G4NEUTRONHPDATA=${GEANT4_DATA_DIR}/G4NDL4.7.1"
set_environment "export G4LEDATA=${GEANT4_DATA_DIR}/G4EMLOW8.5"
set_environment "export G4LEVELGAMMADATA=${GEANT4_DATA_DIR}/PhotonEvaporation5.7"
set_environment "export G4RADIOACTIVEDATA=${GEANT4_DATA_DIR}/RadioactiveDecay5.6"
set_environment "export G4PARTICLEXSDATA=${GEANT4_DATA_DIR}/G4PARTICLEXS4.0"
set_environment "export G4PIIDATA=${GEANT4_DATA_DIR}/G4PII1.3"
set_environment "export G4REALSURFACEDATA=${GEANT4_DATA_DIR}/RealSurface2.2"
set_environment "export G4SAIDXSDATA=${GEANT4_DATA_DIR}/G4SAIDDATA2.0"
set_environment "export G4ABLADATA=${GEANT4_DATA_DIR}/G4ABLA3.3"
set_environment "export G4INCLDATA=${GEANT4_DATA_DIR}/G4INCL1.2"
set_environment "export G4ENSDFSTATEDATA=${GEANT4_DATA_DIR}/G4ENSDFSTATE2.3"


echo " " >> ~/.bashrc
echo "## <-- Added by Geant4 installation script" >> ~/.bashrc

echo -e "${RED}Please execute command < ${GREEN}source ~/.bashrc${RED} > or re-open a terminal for the system to be able to find the databases and libraries.${NC}"



