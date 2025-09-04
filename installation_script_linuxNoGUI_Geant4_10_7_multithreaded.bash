#!/bin/bash
set -euo pipefail

#####################################
# Logging helpers
#####################################
log() { echo -e "[INFO] $*"; }
log_warn() { echo -e "[WARN] $*"; }
log_success() { echo -e "[OK]   $*"; }

#####################################
# Setup working directory
#####################################
mkdir -p geant4
cd geant4

#####################################
# Versions & URLs
#####################################
G4_VERSION="10.7.p04"
_G4_VERSION="10.07.p04"
FOLDER_G4_VERSION="Geant4-10.7.4"
G4_URL="http://cern.ch/geant4-data/releases/geant4.${_G4_VERSION}.tar.gz"

CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v3.14.3/cmake-3.14.3-Linux-x86_64.tar.gz"

XERCES_VERSION="3.2.3"
XERCES_ARCHIVE="xerces-c-${XERCES_VERSION}.tar.gz"
XERCES_URL="http://archive.apache.org/dist/xerces/c/3/sources/${XERCES_ARCHIVE}"

CADMESH_VERSION="1.1"
CADMESH_ARCHIVE="v${CADMESH_VERSION}.tar.gz"
CADMESH_URL="https://github.com/DavidSarria89/CADMesh/releases/download/v1.1mod/v1.1.tar.gz"

#####################################
# Directories
#####################################
BASE_DIR="${PWD}"
CMAKE_PATH="${BASE_DIR}/cmake/bin/cmake"
CORE_NB=$(grep -c ^processor /proc/cpuinfo)

SRC_DIR="${BASE_DIR}/source_geant4.${_G4_VERSION}"
BUILD_DIR="${BASE_DIR}/geant4_build_${_G4_VERSION}"
INSTALL_DIR="${BASE_DIR}/geant4_install_${_G4_VERSION}"
GEANT4_LIB_DIR="${INSTALL_DIR}/lib/${FOLDER_G4_VERSION}"

XERCESC_BUILD_DIR="${BASE_DIR}/build_xercesc_g4_${_G4_VERSION}"
XERCESC_INSTALL_DIR="${BASE_DIR}/install_xercesc_g4_${_G4_VERSION}"
XERCESC_INC_DIR="${XERCESC_INSTALL_DIR}/include"
XERCESC_LIB="${XERCESC_INSTALL_DIR}/lib64/libxerces-c-3.2.so"

CADMESH_BUILD_DIR="${BASE_DIR}/build_cadmesh_g4_${_G4_VERSION}"
CADMESH_INSTALL_DIR="${BASE_DIR}/install_cadmesh_g4_${_G4_VERSION}"

mkdir -p \
  "${SRC_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}" \
  "${CADMESH_BUILD_DIR}" "${CADMESH_INSTALL_DIR}" \
  "${XERCESC_BUILD_DIR}" "${XERCESC_INSTALL_DIR}"

#####################################
# Download & Install CMake
#####################################
log "Installing CMake..."
rm -rf cmake cmake-3.14.3-Linux-x86_64 cmake-3.14.3-Linux-x86_64.tar.gz
wget -q "${CMAKE_URL}"
tar zxf cmake-3.14.3-Linux-x86_64.tar.gz
mv cmake-3.14.3-Linux-x86_64 cmake
rm -f cmake-3.14.3-Linux-x86_64.tar.gz
log_success "CMake installed."

#####################################
# Download & Build Xerces-C
#####################################
log "Building Xerces-C..."
wget -q "${XERCES_URL}"
tar zxf "${XERCES_ARCHIVE}"
rm -f "${XERCES_ARCHIVE}"
XERCES_SRC="${BASE_DIR}/xerces-c-${XERCES_VERSION}"

cd "${XERCESC_BUILD_DIR}"
rm -f CMakeCache.txt

"${CMAKE_PATH}" \
  -DCMAKE_INSTALL_PREFIX="${XERCESC_INSTALL_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_LIBDIR=lib64 \
  "${XERCES_SRC}"

make -j"${CORE_NB}" G4VERBOSE=1
make install
log_success "Xerces-C installed."

cd "${BASE_DIR}"

#####################################
# Download & Build Geant4
#####################################
log "Building Geant4..."
rm -rf "${SRC_DIR}"
wget -q "${G4_URL}"
tar zxf "geant4.${_G4_VERSION}.tar.gz"
mv "geant4.${_G4_VERSION}" "${SRC_DIR}"
rm -f "geant4.${_G4_VERSION}.tar.gz"

cd "${BUILD_DIR}"
rm -f CMakeCache.txt

"${CMAKE_PATH}" \
  -DCMAKE_PREFIX_PATH="${XERCESC_INSTALL_DIR}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGEANT4_BUILD_MULTITHREADED=ON \
  -DGEANT4_INSTALL_DATA=ON \
  -DGEANT4_USE_GDML=ON \
  -DGEANT4_USE_G3TOG4=ON \
  -DGEANT4_USE_QT=OFF \
  -DGEANT4_FORCE_QT4=OFF \
  -DGEANT4_USE_XM=OFF \
  -DGEANT4_USE_OPENGL_X11=OFF \
  -DGEANT4_USE_INVENTOR=OFF \
  -DGEANT4_USE_RAYTRACER_X11=OFF \
  -DGEANT4_USE_SYSTEM_CLHEP=OFF \
  -DGEANT4_USE_SYSTEM_EXPAT=OFF \
  -DGEANT4_USE_SYSTEM_ZLIB=OFF \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DXERCESC_INCLUDE_DIR="${XERCESC_INC_DIR}" \
  -DXERCESC_LIBRARY="${XERCESC_LIB}" \
  "../source_geant4.${_G4_VERSION}"

make -j"${CORE_NB}" G4VERBOSE=1
make install
log_success "Geant4 installed."

cd "${BASE_DIR}"

#####################################
# Environment Setup
#####################################
setup_environment() {
    log "Configuring environment in ~/.bashrc..."
    local START_MARKER="## --> Added by Geant4 installation script"
    local END_MARKER="## <-- Added by Geant4 installation script"

    # Clean previous entries
    sed -i.bak "/${START_MARKER}/,/${END_MARKER}/d" ~/.bashrc || true

    # Add new configuration
    {
        echo "${START_MARKER}"
        echo "source ${INSTALL_DIR}/bin/geant4.sh"
        echo "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:${XERCESC_INC_DIR}"
        echo "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:${XERCESC_INC_DIR}"
        echo "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:${XERCESC_INSTALL_DIR}/lib64"
        echo "export LIBRARY_PATH=\$LIBRARY_PATH:${XERCESC_INSTALL_DIR}/lib64"
        echo "${END_MARKER}"
    } >> ~/.bashrc

    log_success "Environment configuration added."
}

setup_environment

#####################################
# Summary
#####################################
log_success "Geant4 installation completed!"
log_warn "Run 'source ~/.bashrc' or restart your terminal to apply environment variables."
