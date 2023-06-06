## Set of bash scripts to easily download, compile and install Geant4 on a *Linux OS* or *Mac OS* using *Bash*.
### `installation_script_Ubuntu_18_04_FullGeant4_10_6.bash` :
- For Ubuntu 18.04 and *includes the window GUI (Qt) and 3D graphics capabilities of Geant4*.
- Set up for version Geant4 10.6 without multithreading activated, but the version and settings should be fairly easily changable by editing the bash file. See also the other scripts available in this folder.
- Use `bash script_name.bash` to execute (it is important to use `bash` and not `sh` only).
- The user must have the *GNU C and C++ compilers* (gcc and g++) accessible in the `$PATH`. E.g. with `sudo apt-get install gcc g++ gfortran` .
- See http://geant4.web.cern.ch/ and the [Geant4 installation instructions](http://geant4-userdoc.web.cern.ch/geant4-userdoc/UsersGuides/InstallationGuide/html/index.html) for more information on what the scripts should be doing.
- For *Windows*, you can check this unofficial installer: https://zenodo.org/record/3571237 (Geant4 10.4, uses Visual Studio and was tested to work on Windows 10).

### `installation_script_linuxNoGUI_Geant4_10_7_multithreaded.bash` :
- Downloads/compiles/installs on a *Linux based OS* with *bash*, **without** GUI and 3D graphics capability. Can be used in computer clusters (HPC) for heavy calculations for example.

### `installation_script_Ubuntu_18_04_FullGeant4_10_6.bash` :
- Does like the previous script, but for a Linux *Ubuntu OS*, and will also **build and install the GUI (Qt) and 3D graphics capabilities of Geant4**.
- It was successfully tested on Ubuntu 16.04 and 18.04, but may not be free of bugs.
- Will require super user priviledges (`sudo`) to download missing dependencies.
- alternatively, run command `sudo apt-get install build-essential qt4-default qtcreator cmake-qt-gui gcc g++ gfortran zlib1g-dev libxerces-c-dev libx11-dev libexpat1-dev libxmu-dev libmotif-dev libboost-filesystem-dev libeigen3-dev qt4-qmake automake libuuid1 uuid-dev uuid-runtime` to install dependencies before-hand, and `sudo` should not be required.

### `***_FullGeant4_10_X_***.bash` :
* Script for a specific version of Geant4 10.X .

### `***_Ubuntu_XX_XX_***.bash` :
* Script for a specific version of Ubuntu XX.XX .

### `***_multithreaded.bash` :
* Script with the multi-threading option enabled (i.e. `-DGEANT4_BUILD_MULTITHREADED=ON`). Note: the resulting Geant4 compiled libraries can be also used (imported) for single threaded applications.

### `installation_script_macOS_Full.bash` :
* Downloads/compiles/installs on *Mac OS* with *bash*, **with** GUI and 3D graphics capability. After install, CMake with Geant4 environement (i.e. the `-DGeant4_DIR=...` variable is set) can be loaded using `launch_CMake_MAC.bash` .
* Requires:
  * Brew, since running the command `brew install qt` to install Qt5 is required.
  * Probably also Xcode installed.
* On Geant4 10.4.3 (and possibly other versions), for multithreaded code to compile (i.e. using multi-threading include files), the user should remove (or comment out) the include `#include <unistd.h>` in the source file `./geant4/geant4_install_10.04.p03/include/Geant4/G4Threading.hh` (line 48).

### `installation_script_macOS_no_GUI.bash` :
- Downloads/compiles/installs on *Mac OS* with *bash*, **without** GUI and 3D graphics capability. After install, CMake with Geant4 environement (i.e. the `-DGeant4_DIR=...` variable is set) can be loaded using `launch_CMake_MAC.bash`.
- On Geant4 10.4.3 (and possibly other versions), for multithreaded code to compile (i.e. using multi-threading include files), the user should remove (or comment out) the include `#include <unistd.h>` in the source file `./geant4/geant4_install_10.04.p03/include/Geant4/G4Threading.hh` (line 48).

### `installation_script_linux_only_matio_hdf5_zlib.bash` :
* Downloads/compiles/installs only `zlib`, `hdf5` and `matio` libraries. That permits to output directly to Matlab `.mat` files. More info about matio: https://github.com/tbeu/matio .

### `installation_script_linux_only_CADmesh.bash` :
* Downloads/compiles/installs only the `CADmesh` libraries to easily load CAD 3D models geometry (`.stp`) into Geant4. See https://github.com/christopherpoole/CADMesh.

