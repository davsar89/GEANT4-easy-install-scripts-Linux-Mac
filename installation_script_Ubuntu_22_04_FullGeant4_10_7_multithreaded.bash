#!/bin/bash
set -euo pipefail

#################
# Create main directory for everything
mkdir -p geant4
cd geant4
#################

########################## VARIABLES

############## PROGRAMS' VERSIONS AND URLs : MAY CHANGE IN THE FUTURE
readonly G4_VERSION="10.7.p04"
readonly _G4_VERSION="10.07.p04"
readonly __G4_VERSION="10.7.4"
readonly FOLDER_G4_VERSION="Geant4-10.7.4"
readonly G4_URL="https://github.com/Geant4/geant4/archive/refs/tags/v${__G4_VERSION}.tar.gz"
readonly G4_ARC="geant4.${_G4_VERSION}.tar.gz"

readonly CMAKE_DOWNLOAD_URL="https://github.com/Kitware/CMake/releases/download/v3.14.3/cmake-3.14.3-Linux-x86_64.tar.gz"

readonly XERCES_W_VER="xerces-c-3.2.2"
readonly XERCES_ARC="${XERCES_W_VER}.tar.gz"
readonly XERCES_URL="https://github.com/apache/xerces-c/archive/refs/tags/v3.2.2.tar.gz"

####################################################

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# Base directories
readonly BASE_DIR="${PWD}"
readonly CURRENT_DIR="${PWD}"

# Core count for parallel compilation
readonly CORE_NB=$(grep -c ^processor /proc/cpuinfo)

# CMake setup
setup_cmake() {
    echo "Setting up CMake..."
    rm -rf cmake cmake-3.14.3-Linux-x86_64 cmake-3.14.3-Linux-x86_64.tar.gz
    
    wget "${CMAKE_DOWNLOAD_URL}"
    tar zxf cmake-3.14.3-Linux-x86_64.tar.gz
    mv cmake-3.14.3-Linux-x86_64 cmake
    rm -rf cmake-3.14.3-Linux-x86_64.tar.gz
    
    echo "CMake setup complete."
}

setup_cmake
readonly CMAKE_PATH="${BASE_DIR}/cmake/bin/cmake"

# Geant4 directories
readonly SRC_DIR="${BASE_DIR}/source_geant4.${_G4_VERSION}/"
readonly BUILD_DIR="${BASE_DIR}/geant4_build_${_G4_VERSION}/"
readonly INSTALL_DIR="${BASE_DIR}/geant4_install_${_G4_VERSION}/"
readonly GEANT4_LIB_DIR="${INSTALL_DIR}/lib/${FOLDER_G4_VERSION}/"

# XERCES-C directories
readonly XERCESC_BUILD_DIR="${BASE_DIR}/build_xercesc_g4_${_G4_VERSION}/"
readonly XERCESC_INSTALL_DIR="${BASE_DIR}/install_xercesc_g4_${_G4_VERSION}/"
readonly XERCESC_INC_DIR="${XERCESC_INSTALL_DIR}/include"
readonly XERCESC_LIB_DIR="${XERCESC_INSTALL_DIR}/lib64/libxerces-c-3.2.so"

########## Create necessary folders
echo "Creating necessary directories..."
mkdir -p "${BUILD_DIR}" "${SRC_DIR}" "${INSTALL_DIR}"
mkdir -p "${XERCESC_BUILD_DIR}" "${XERCESC_INSTALL_DIR}"
echo "Directories created."

############# CHECK IF OS IS UBUNTU
check_ubuntu() {
    echo "Checking if OS is Ubuntu..."
    
    if [[ ! -f /etc/os-release ]]; then
        echo "Error: Cannot determine OS. /etc/os-release not found. Aborting."
        exit 1
    fi
    
    # shellcheck source=/etc/os-release
    . /etc/os-release
    local os_name="$NAME"
    
    if [[ "$os_name" != "Ubuntu" ]]; then
        echo "Error: OS is not Ubuntu. Script works only for Ubuntu. Aborting."
        exit 1
    fi
    
    echo "... OS is Ubuntu"
}

check_ubuntu

#########################################################################
############# CHECK IF DEPENDENCIES ARE SATISFIED, OTHERWISE INSTALL THEM

readonly UBUNTU_DEPENDENCIES=(
    "build-essential"
    "qtcreator"
    "qtbase5-dev"
    "cmake-qt-gui"
    "gcc"
    "g++"
    "gfortran"
    "zlib1g-dev"
    "libxerces-c-dev"
    "libx11-dev"
    "libexpat1-dev"
    "libxmu-dev"
    "libmotif-dev"
    "libboost-filesystem-dev"
    "libeigen3-dev"
    "libuuid1"
    "uuid-dev"
    "uuid-runtime"
)

ENTERED_ONE_TIME=true

run_install() {
    echo "Some missing dependencies were detected."
    
    # Prompt for sudo access
    if [[ "$ENTERED_ONE_TIME" == true ]]; then
        ENTERED_ONE_TIME=false
        read -rp "Do you have (root) sudo access? [Y/n]. It is required to install missing dependencies: " answer
        answer=${answer:-Y}  # Default to Y if no answer given
        
        if [[ $answer =~ [Nn] ]]; then
            echo "Root access is required to install missing dependencies. Aborting."
            exit 1
        fi
    fi
    
    # Prompt for installation
    read -rp "Do you want to install missing dependencies? [Y/n]: " answer
    answer=${answer:-Y}  # Default to Y if no answer given
    
    if [[ $answer =~ [Yy] ]]; then
        sudo apt-get update
        sudo apt-get install -y "${UBUNTU_DEPENDENCIES[@]}"
    else
        echo "Missing dependencies are required for proper compilation and installation. Aborting."
        exit 1
    fi
}

check_dependencies() {
    echo "Checking dependencies..."
    
    # Check if all dependencies are installed
    if ! dpkg -s "${UBUNTU_DEPENDENCIES[@]}" >/dev/null 2>&1; then
        run_install
    fi
    
    echo "... dependencies are satisfied."
}

check_dependencies

#########################################################################

#### XERCES-C (to be able to use GDML files)

build_xerces() {
    echo "Building Xerces-C..."
    
    # Download xerces-c (for GDML)
    rm -rf v3.2.2.tar.gz*
    wget "${XERCES_URL}"
    mv v3.2.2.tar.gz "${XERCES_ARC}"
    tar zxf "${BASE_DIR}/${XERCES_ARC}"
    rm -rf "${XERCES_ARC}"
    
    local xerces_src="${BASE_DIR}/${XERCES_W_VER}"
    
    # Compile and install xerces-c
    cd "${XERCESC_BUILD_DIR}"
    
    echo "Build of xerces-c: Executing CMake..."
    rm -rf CMakeCache.txt
    
    "${CMAKE_PATH}" \
        -DCMAKE_INSTALL_PREFIX="${XERCESC_INSTALL_DIR}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        "${xerces_src}"
    
    echo "... done"
    
    echo "Compiling and installing xerces-c..."
    G4VERBOSE=1 make -j"${CORE_NB}"
    make install
    
    cd "${BASE_DIR}"
    echo "Xerces-C build complete."
}

build_xerces

#### GEANT4

build_geant4() {
    echo "Building Geant4..."
    
    # Download Geant4
    rm -rf "v${__G4_VERSION}.tar.gz"*
    rm -rf "${SRC_DIR}"
    
    wget "${G4_URL}"
    mv "v${__G4_VERSION}.tar.gz" "${G4_ARC}"
    tar zxf "${G4_ARC}"
    mv "geant4-${__G4_VERSION}" "${SRC_DIR}"
    rm -rf "geant4.${_G4_VERSION}.tar.gz"
    
    # Compile and install Geant4
    cd "${BUILD_DIR}"
    rm -rf CMakeCache.txt
    
    echo "Build Geant4: Executing CMake..."
    
    "${CMAKE_PATH}" \
        -DCMAKE_PREFIX_PATH="${XERCESC_INSTALL_DIR}" \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
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
        -DGEANT4_USE_SYSTEM_EXPAT=OFF \
        -DGEANT4_USE_SYSTEM_ZLIB=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DXERCESC_INCLUDE_DIR="${XERCESC_INC_DIR}" \
        -DXERCESC_LIBRARY="${XERCESC_LIB_DIR}" \
        "../source_geant4.${_G4_VERSION}/"
    
    echo "... Done"
    
    echo "Compiling and installing Geant4..."
    G4VERBOSE=1 make -j"${CORE_NB}"
    make install
    
    cd "${BASE_DIR}"
    echo "Geant4 build complete."
}

build_geant4

#########################################################################
#### Set environment variables in '~/.bashrc'

setup_environment_variables() {
    echo "Setting up environment variables..."
    
    # Clean environment that was previously set by this script
    local first_line
    local last_line
    
    first_line=$(grep -n "## --> Added by Geant4 installation script" ~/.bashrc | awk -F: '{print $1}' || true)
    last_line=$(grep -n "## <-- Added by Geant4 installation script" ~/.bashrc | awk -F: '{print $1}' || true)
    
    local re='^[0-9]+$'
    if [[ $first_line =~ $re && $last_line =~ $re ]]; then
        # Create backup and remove old environment setup
        sed -i.bak "${first_line},${last_line}d" ~/.bashrc
    fi
    
    # Add header comment
    echo "## --> Added by Geant4 installation script" >> ~/.bashrc
    
    # Function to set environment variable
    set_environment_var() {
        local env_var="$1"
        
        cd "${BASE_DIR}"
        
        if grep -Fxq "$env_var" ~/.bashrc; then
            echo -e "${GREEN}< $env_var > already set up in ~/.bashrc.${NC}"
        else
            echo "    " >> ~/.bashrc
            echo "$env_var" >> ~/.bashrc
            echo "______"
            echo -e "${GREEN}Added ${RED}$env_var${GREEN} to ${RED}~/.bashrc${GREEN} file.${NC}"
        fi
    }
    
    # Geant4 + data
    set_environment_var "source ${INSTALL_DIR}/bin/geant4.sh"
    
    # xerces-c
    set_environment_var "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:${XERCESC_INSTALL_DIR}/include/"
    set_environment_var "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:${XERCESC_INSTALL_DIR}/include/"
    set_environment_var "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:${XERCESC_INSTALL_DIR}/lib64/"
    set_environment_var "export LIBRARY_PATH=\$LIBRARY_PATH:${XERCESC_INSTALL_DIR}/lib64/"
    set_environment_var "export PATH=\$PATH:${XERCESC_INSTALL_DIR}/include/"
    
    # Add footer comment
    echo " " >> ~/.bashrc
    echo "## <-- Added by Geant4 installation script" >> ~/.bashrc
    
    echo "Environment variables setup complete."
    echo -e "${RED}Please execute command < ${GREEN}source ~/.bashrc${RED} > or re-open a terminal for the system to be able to find the databases and libraries.${NC}"
}

setup_environment_variables
