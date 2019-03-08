#!/bin/bash
set -e

#################
mkdir -p geant4 # directory were everything is built and installed
cd geant4
############# 

########################## VARIABLES

##############  PROGRAMS' VERSIONS AND URLs : MAY CHANGE IN THE FUTURE
#g4_version=10.5
#_g4_version=10.05
g4_version=10.4.p03
_g4_version=10.04.p03
folder_g4_version=Geant4-10.4.3
g4_url=("http://cern.ch/geant4-data/releases/geant4.${_g4_version}.tar.gz")

xerces_w_ver=xerces-c-3.2.0
xerces_arc=${xerces_w_ver}.tar.gz
xerces_url=("http://archive.apache.org/dist/xerces/c/3/sources/$xerces_arc")

casmesh_w_ver=1.1
casmesh_arc=v${casmesh_w_ver}.tar.gz
casmesh_url=("https://github.com/christopherpoole/CADMesh/archive/v$casmesh_w_ver.tar.gz")

matio_git_repo=git://git.code.sf.net/p/matio/matio

hdf5_git_repo=https://git.hdfgroup.org/scm/hdffv/hdf5.git
hdf5_src_foldername=hdf5_1_10_1
hdf5_branch=hdf5_1_10_1

zlib_src=zlib-1.2.11
zlib_ar_name=$zlib_src.tar.gz
zlib_url=https://www.zlib.net/$zlib_ar_name

####################################################

# CMake command
CMake_path=../../cmake/bin/cmake

#
current_dir=$PWD

# Parameters
core_nb=`grep -c ^processor /proc/cpuinfo`

base_dir=$PWD

# Geant4
src_dir=$base_dir/source_geant4.${_g4_version}/
build_dir=$base_dir/geant4_build_${_g4_version}/
install_dir=$base_dir/geant4_install_${_g4_version}/
geant4_lib_dir=${install_dir}/lib/${folder_g4_version}/

# XERCES-C

xercesc_build_dir=($base_dir/build_xercesc/)
xercesc_install_dir=($base_dir/install_xercesc/)
xercesc_inc_dir=(${xercesc_install_dir}/include)
xercesc_lib_dir=(${xercesc_install_dir}/lib64/libxerces-c-3.2.so)

# CADMESH

casmesh_build_dir=($base_dir/build_cadmesh/)
casmesh_install_dir=($base_dir/install_cadmesh/)

# MATIO

matio_build_dir=($base_dir/build_matio/)
matio_install_dir=($base_dir/install_matio/)
matio_name_ver=matio-1.5.13
matio_folder_name=($base_dir/$matio_name_ver/)

# HDF5

hdf5_build_dir=($base_dir/build_hdf5/)
hdf5_install_dir=($base_dir/install_hdf5/)

# ZLIB

zlib_build_dir=($base_dir/build_zlib/)
zlib_install_dir=($base_dir/install_zlib/)

########## Creating folders

  mkdir -p ${build_dir} # -p will create only if it does not exist yet
  mkdir -p ${src_dir}
  mkdir -p ${install_dir}

  mkdir -p $casmesh_build_dir
  mkdir -p $casmesh_install_dir

  mkdir -p $xercesc_build_dir
  mkdir -p $xercesc_install_dir

  mkdir -p $hdf5_build_dir
  mkdir -p $hdf5_install_dir

  mkdir -p $matio_build_dir
  mkdir -p $matio_install_dir


#### ZLIB (requirement of MATIO and HDF5)

echo "Attempt to download, compile and install ZLIB..."
rm -rf $zlib_ar_name
wget -N $zlib_url
tar zxf $zlib_ar_name
cd $zlib_src
CC=gcc CXX=g++ ./configure --prefix=$zlib_install_dir \
                           --eprefix=$zlib_install_dir
make
make install
echo "... done"

#### HDF5 (requirement of MATIO)

echo "Attempt to download HDF5 source..."

rm -rf $hdf5_src_foldername

git clone --branch $hdf5_branch $hdf5_git_repo $hdf5_src_foldername

cd $hdf5_src_foldername  

echo "... done"

echo "Attempt to configure Autotools of HDF5..."
CC=gcc CXX=g++ ./configure --with-zlib=$zlib_install_dir \
                           --enable-cxx --enable-fortran \
                           --quiet --enable-shared --enable-build-mode=debug --disable-deprecated-symbols \
                           --disable-hl --disable-strict-format-checks --disable-memory-alloc-sanity-check \
                           --disable-instrument --disable-parallel --disable-trace --disable-internal-debug \
                           --enable-optimization=debug --disable-asserts --with-pic --with-default-api-version=v110 CFLAGS="-w"

echo "... done"

echo "Attempt to compile and install hdf5"

make install -C src

rm -rf $hdf5_install_dir

mv ./hdf5 $hdf5_install_dir

cd $base_dir
echo "... done"

#### MATIO (to be able to write matlab output files)

#rm -rf $matio_name_ver.tar.gz*
#rm -rf $matio_folder_name
#wget -N https://github.com/tbeu/matio/releases/download/v1.5.13/$matio_name_ver.tar.gz
#tar zxf matio-1.5.13.tar.gz
#cd $matio_folder_name

rm -rf matio
git clone $matio_git_repo
cd matio
#git submodule update --init  # for datasets used in unit tests
git reset --hard 9f7f96d727dc0408fd3a1364bea067524b246de6 # specific commit where we know it works
./autogen.sh

echo "build of matio: Attempt to execute Autotools..."

CC=gcc CXX=g++ ./configure --with-default-file-ver=7.3 \
                           --with-hdf5=${hdf5_install_dir} \
                           --prefix=$matio_install_dir \
                           --with-default-api-version=v110 \
                           --enable-mat73=yes \
                           --with-zlib=$zlib_install_dir \
                           --exec-prefix=$matio_install_dir

echo "... done"

echo "Attempt to compile and install matio"
make
#make check
make install

cd $base_dir
echo "... done"

#### XERCES-C (to be able to use GDML files)

## download xerces-c (for GDML)

wget $xerces_url
tar zxf $base_dir/$xerces_arc
rm -rf $xerces_arc

xerces_src=$base_dir/$xerces_w_ver

## compile and install xerces-c

cd $xercesc_build_dir

echo "build of xerces-c: Attempt to execute CMake..."

rm -rf CMakeCache.txt

$CMake_path \
      -DCMAKE_INSTALL_PREFIX=${xercesc_install_dir} \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_LIBDIR=lib64 \
      $xerces_src
echo "... done"

echo "Attempt to compile and install xerces-c"

  G4VERBOSE=1 make -j${core_nb}
  make install

cd $base_dir
echo "... done"

#### GEANT4

## download Geant4

rm -rf ${src_dir}
wget $g4_url
tar zxf geant4.${_g4_version}.tar.gz
mv geant4.${_g4_version} ${src_dir}
rm -rf geant4.${_g4_version}.tar.gz

## compile and install Geant4

  cd ${build_dir}
  rm -rf CMakeCache.txt

echo "build_geant4: Attempt to execute CMake"
  
      $CMake_path \
      -DCMAKE_INSTALL_PREFIX=${install_dir} \
      -DCMAKE_BUILD_TYPE=Release \
      -DGEANT4_BUILD_MULTITHREADED=OFF \
      -DGEANT4_BUILD_CXXSTD=c++11 \
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
      -DXERCESC_INCLUDE_DIR=${xercesc_inc_dir} \
      -DXERCESC_LIBRARY=${xercesc_lib_dir} \
      ../source_geant4.${_g4_version}/

echo "... Done"

echo "Attempt to compile and install Geant4"

  G4VERBOSE=1 make -j${core_nb}

  make install

cd $base_dir
echo "... Done"

#### CADMESH
# CADMESH is a CAD file interface for GEANT4, made by Poole, C. M. et al.
# See https://github.com/christopherpoole/CADMesh

## download CADMESH

wget $casmesh_url
tar zxf $base_dir/$casmesh_arc
rm -rf $casmesh_arc

casmesh_src=$base_dir/CADMesh-$casmesh_w_ver

## compile and install CADMESH

cd $casmesh_build_dir

echo "build of CADMESH: Attempt to execute CMake..."

rm -rf CMakeCache.txt

$CMake_path \
      -DCMAKE_INSTALL_PREFIX=${casmesh_install_dir} \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DGeant4_DIR=$geant4_lib_dir \
      $casmesh_src

echo "... done"

echo "Attempt to compile and install CADMESH"

  G4VERBOSE=1 make -j${core_nb}
  make install

cd $base_dir

echo "... done"


#########################################################################
#########################################################################
#### set environement variables into '~/.bashrc'

echo "Attempt to setup up environement variables..."

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "## --> Added by matio_hdf5_zlib installation script" >> ~/.bashrc

set_environement() {

cd $base_dir

  if grep -Fxq "$1" ~/.bashrc
  then
    echo -e "${GREEN}< source $1 > already set up in ~/.bashrc.${NC}"          
  else
    echo "    " >> ~/.bashrc
    echo $1 >> ~/.bashrc
    echo "______"
    echo -e "${GREEN}added ${RED}$1${GREEN} to ${RED}~/.bashrc${GREEN} file.${NC}"
  fi
}

# Geant4 + data
set_environement "source $install_dir/bin/geant4.sh"

# CADMesh
set_environement "export cadmesh_DIR=$casmesh_install_dir/lib/cmake/cadmesh-1.1.0/"
set_environement "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:$casmesh_install_dir/include/"
set_environement "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:$casmesh_install_dir/include/"
set_environement "export PATH=\$PATH:$casmesh_install_dir/include/"
set_environement "export LIBRARY_PATH=\$LIBRARY_PATH:$casmesh_install_dir/lib/"
set_environement "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:$casmesh_install_dir/lib/"

# xerces-c
set_environement "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:$xercesc_install_dir/include/"
set_environement "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:$xercesc_install_dir/include/"
set_environement "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:$xercesc_install_dir/lib64/"
set_environement "export LIBRARY_PATH=\$LIBRARY_PATH:$xercesc_install_dir/lib64/"
set_environement "export PATH=\$PATH:$xercesc_install_dir/include/"

# matio
set_environement "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:$matio_install_dir/include/"
set_environement "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:$matio_install_dir/include/"
set_environement "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:$matio_install_dir/lib/"
set_environement "export LIBRARY_PATH=\$LIBRARY_PATH:$matio_install_dir/lib/"
set_environement "export PATH=\$PATH:$matio_install_dir/include/"

# hdf5
set_environement "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:$hdf5_install_dir/include/"
set_environement "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:$hdf5_install_dir/include/"
set_environement "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:$hdf5_install_dir/lib/"
set_environement "export LIBRARY_PATH=\$LIBRARY_PATH:$hdf5_install_dir/lib/"
set_environement "export PATH=\$PATH:$hdf5_install_dir/include/"

set_environement "export HDF5_ROOT=$hdf5_install_dir"
set_environement "export HDF5_DIR=$hdf5_install_dir"

# zlib
set_environement "export C_INCLUDE_PATH=\$C_INCLUDE_PATH:$zlib_install_dir/include/"
set_environement "export CPLUS_INCLUDE_PATH=\$CPLUS_INCLUDE_PATH:$zlib_install_dir/include/"
set_environement "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:$zlib_install_dir/lib/"
set_environement "export LIBRARY_PATH=\$LIBRARY_PATH:$zlib_install_dir/lib/"
set_environement "export PATH=\$PATH:$zlib_install_dir/include/"

echo "## <-- Added by matio_hdf5_zlib installation script" >> ~/.bashrc

echo "... Done"
echo -e "${RED}Please excecute command < ${GREEN}source ~/.bashrc${RED} > or re-open a terminal for the system to be able to find the databases and libraries.${NC}"



