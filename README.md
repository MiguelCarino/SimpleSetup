# SimpleSetup
*Simple setup* scripts (not short though) **for Linux and Windows systems**. So the user don't worry about choices besides their actual use case.\
**Systems supported:**\
*Linux:*\
**Debian** and derivatives with package name compatibility.\
**Fedora** and derivatives with package name compatibility.\
*Windows:*\
**Windows 10**\
**Windows 11**\

**Main features:**\
*Automatically identifies your distro.\
*Quick setup: Just install and forget.\
*Technical Setup: Installs whatever packages you need for a decent hardware experience and basic user features, like Nvidia drivers, Rocm/Hip, non-free repos, Flathub, a Desktop Environment if missing, dark theme, dot files, etc.\
*Purpose Setup: Installs necessary packages for a given purpose. Like Astronomy, Graphic Design, Forensics, and more.\
*You can select another specific option in the menu, like installing an extra Desktop Environment.\
*Arguments are supported.\
*Language menus in English, Japanese, Russian, Spanish, Finnish, Chinese, Korean, Hebrew with automatic locale detection.\

**Arguments**
*All arguments are used after setup.sh*\
bash <(curl -s https://carino.systems/setup.sh) **argument**\
./setup.sh **argument**\

*quick\
Execute technical Setup and Basic purpose package installation. The simplest way.
*simple\
Execute technical Setup and Basic purpose package installation. The simplest way.
*server\
Execute a simple server setup with some development packages. Doesn't consider technical setup.
*desktop\
Shows a menu to install a Desktop Environment from a list.
*nvidia\
*amd\
*intel\
*aspeed\
*matrox\
These options execute graphic driver installation.
*svp\
Installs Smooth Video Project.
*protonge\
Install the latest version of protonge.
*distrobox\
Install distrobox containers.
