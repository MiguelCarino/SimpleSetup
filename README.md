# SimpleSetup
*Simple setup* scripts (not short though) **for Linux and Windows systems**. So the user doesn't need to worry about choices besides their actual use case.  
**Systems supported:**  
*Linux:*  
- **Debian** and derivatives with package name compatibility.  
- **Fedora** and derivatives with package name compatibility.  

*Windows:*  
- **Windows 10**  
- **Windows 11**  

## Main Features
- **Automatic distro identification**
- **Quick setup**: Install and forget
- **Technical Setup**: Installs necessary packages for a decent hardware experience and basic user features (e.g., Nvidia drivers, Rocm/Hip, non-free repos, Flathub, Desktop Environment if missing, dark theme, dot files, etc.)
- **Purpose Setup**: Installs specific packages for chosen purposes (e.g., Astronomy, Graphic Design, Forensics, etc.)
- **Menu options**: Choose extra setups like installing an additional Desktop Environment
- **Argument support**
- **Multilingual menus**: English, Japanese, Russian, Spanish, Finnish, Chinese, Korean, Hebrew, with automatic locale detection

## Arguments
*All arguments are used after `setup.sh`*  
```bash
bash <(curl -s https://carino.systems/setup.sh) **argument**
./setup.sh **argument**

### General Arguments
- **quick**  
  Installs Technical Setup and Basic Purpose packages for a fast and straightforward installation.

- **simple**  
  Performs the Technical Setup and Basic Purpose package installation. This option provides a hassle-free setup.

- **server**  
  Configures a minimal server setup with essential development packages. This does not include the full Technical Setup.

### Graphics Driver Installation
- **nvidia**  
  Installs Nvidia graphic drivers.

- **amd**  
  Installs AMD graphic drivers.

- **intel**  
  Installs Intel graphic drivers.

- **aspeed**  
  Installs Aspeed graphic drivers.

- **matrox**  
  Installs Matrox graphic drivers.

### Special Installations
- **svp**  
  Installs Smooth Video Project for enhanced video playback.

- **protonge**  
  Installs the latest version of Proton GE for improved gaming performance on Linux.

- **distrobox**  
  Installs Distrobox containers for running multiple Linux distributions seamlessly.

### Desktop Environment Setup
- **desktop**  
  Opens a menu to select and install a Desktop Environment from a curated list.
