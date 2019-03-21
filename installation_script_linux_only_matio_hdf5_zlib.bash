#!/bin/bash
set -e

#################
mkdir -p geant4 # directory were everything is built and installed
cd geant4
base_dir=$PWD
#############

########################## VARIABLES

##############  PROGRAMS' VERSIONS AND URLs : MAY CHANGE IN THE FUTURE

cmake_download_url=https://github.com/Kitware/CMake/releases/download/v3.14.3/cmake-3.14.3-Linux-x86_64.tar.gz

matio_git_repo=https://github.com/tbeu/matio.git

hdf5_ar=hdf5-hdf5-1_10_1.tar.gz
hdf5_ar_url=https://github.com/DavidSarria89/HDF5_g4/releases/download/1.10.1/$hdf5_ar
hdf5_src_foldername=hdf5-hdf5-1_10_1
hdf5_branch=hdf5_1_10

zlib_src=zlib-1.2.11
zlib_ar_name=$zlib_src.tar.gz
zlib_url=https://github.com/DavidSarria89/zlib/releases/download/1.2.11/$zlib_ar_name

####################################################

# getting CMake
rm -rf cmake
rm -rf cmake-3.14.3-Linux-x86_64
rm -rf cmake-3.14.3-Linux-x86_64.tar.gz
wget ${cmake_download_url}
tar zxf cmake-3.14.3-Linux-x86_64.tar.gz
mv cmake-3.14.3-Linux-x86_64 cmake
rm -rf cmake-3.14.3-Linux-x86_64.tar.gz

# CMake command
CMake_path=${base_dir}/cmake/bin/cmake

#
current_dir=$PWD

# Parameters
core_nb=`grep -c ^processor /proc/cpuinfo`

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

mkdir -p $matio_build_dir
mkdir -p $matio_install_dir

mkdir -p $hdf5_build_dir
mkdir -p $hdf5_install_dir

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
cd $base_dir
echo "... done"

#### HDF5 (requirement of MATIO)

echo "Attempt to download HDF5 source..."

rm -rf $hdf5_src_foldername

wget -N $hdf5_ar_url
tar zxf $hdf5_ar

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
git reset --hard adfa218770183cf93f74e7fad5055921ae1f9958 # specific commit where we know it works
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


#########################################################################
#########################################################################
#### set environement variables into '~/.bashrc'

echo "Attempt to setup up environement variables..."

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# clean environement that was previously set by this script
first_line=`grep -n "## --> Added by hdf5 zlib matio installation script" ~/.bashrc | awk -F  ":" '{print $1}'`
echo $first_line
last_line=`grep -n "## <-- Added by hdf5 zlib matio installation script" ~/.bashrc | awk -F  ":" '{print $1}'`
echo $last_line

re='^[0-9]+$'
if [[ $first_line =~ $re ]] ; then # if $first_line is a number (i.e. it was found)
    if [[ $last_line =~ $re ]] ; then # if $last_line is a number (i.e. it was found)
        sed -i.bak "${first_line},${last_line}d" ~/.bashrc # delete text in .bashrc from first-line to last-line
    fi
fi

#

echo "## --> Added by hdf5 zlib matio installation script" >> ~/.bashrc

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

echo "## <-- Added by hdf5 zlib matio installation script" >> ~/.bashrc

echo "... Done"
echo -e "${RED}Please excecute command < ${GREEN}source ~/.bashrc${RED} > or re-open a terminal for the system to be able to find the databases and libraries.${NC}"



