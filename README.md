## Bash script to easily download, compile and install Geant4 on a Linux OS with bash.
- Use `bash script_name.bash` to execute
- See http://geant4.web.cern.ch/ and the [Geant4 installation instructions](http://geant4-userdoc.web.cern.ch/geant4-userdoc/UsersGuides/InstallationGuide/html/index.html) for more information on what the scripts should be doing

### `installation_script_linux_no_GUI.bash` :
- Downloads/compiles/installs on a *Linux based OS* with *bash*, **without** GUI and 3D graphics capability
- The user have a *C/C++ compiler* accessible in the `$PATH`

### `installation_script_Ubuntu_Full.bash` :
- Does like the previous script, but for a Linux *Ubuntu OS*, and will also **build the GUI and 3D graphics capabilities of Geant4**
- It was successfully tested on Ubuntu 16.04 and 18.04, but is probably not free of bugs
- Will require super user priviledges (`sudo`) to download missing dependencies
- alternatively, run command `sudo apt-get install build-essential qt4-default qtcreator cmake-qt-gui gcc g++ gfortran zlib1g-dev libxerces-c-dev libx11-dev libexpat1-dev libxmu-dev libmotif-dev libboost-filesystem-dev libeigen3-dev qt4-qmake` to install dependencies before-hand, and `sudo` should not be required

