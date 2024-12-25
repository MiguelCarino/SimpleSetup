#!/bin/bash
# Setup script
# Log all output to file
currentDate=$(date +%Y%M%D)
LOG=carino-setup$version.log
exec > >(tee -a "$LOG") 2>&1
# Defining Global Variables
RED="\e[31m"; BLUE="\e[94m"; GREEN="\e[32m"; YELLOW="\e[33m"; ENDCOLOR="\e[0m";USERNAME="MiguelCarino"; REPO="Carino-Systems"; latest_commit=$(curl -s "https://api.github.com/repos/$USERNAME/$REPO/commits?per_page=1" | jq -r '.[0].commit.message');latest_commit_time=$(curl -s "https://api.github.com/repos/$USERNAME/$REPO/commits?per_page=1" | grep -m 1 '"date":' | awk -F'"' '{print $4}');latest_kernel=$(curl -s https://www.kernel.org/releases.json | jq -r '.releases[1].version');hardwareAcceleration=$(glxinfo | grep "direct rendering");hardwareRenderer=$(glxinfo | grep "direct rendering" | awk '{print $3}');archType=$(lscpu | grep -e "^Architecture:" | awk '{print $NF}'); locale_language=$(locale | grep "LANG=" | cut -d'=' -f2)
# Localized Display Menus
tech_setup_en_US="-------------------------------------\nSetup Script\n-------------------------------------\nVersion:1.1\nDetected Distribution: $NAME $VERSION\nLatest GitHub Commit: $latest_commit\nLatest Linux Kernel Version: $latest_kernel\nYour Kernel Version: $(uname -r)\nCPU Architecture: $archType\nHardware acceleration enabled: $hardwareAcceleration\nHardware renderer: $hardwareRenderer\n-------------------------------------\nPlease select an option:\n1. Technical Setup\n2. Purpose Setup\n3. Install a Desktop Environment\n4. Install graphic drivers\n5. Install latest protonGE release\n6. Distro demo\n7. Exit"
tech_setup_ja_JP="-------------------------------------\nセットアップ スクリプト\n-------------------------------------\nバージョン:1.1\n検出されたディストリビューション： $DISTRIBUTION $VERSION_ID\n最新のGitHubコミット： $latest_commit\n最新のLinuxカーネルバージョン： $latest_kernel\nあなたのカーネルバージョン： $(uname -r)\nCPUアーキテクチャ： $archType\nハードウェアアクセラレーションが有効： $hardwareAcceleration\nハードウェアレンダラー： $hardwareRenderer\n-------------------------------------\nオプションを選択してください：\n1. 技術的なセットアップ\n2. 目的のセットアップ\n3. デスクトップ環境のインストール\n4. グラフィックドライバーのインストール\n5. 最新のProtonGEリリースのインストール\n6. ディストロのデモ\n7. 終了"
tech_setup_ru_RU="-------------------------------------\nСкрипт установки\n-------------------------------------\nВерсия:1.1\nОбнаруженное распространение: $DISTRIBUTION $VERSION_ID\nПоследний коммит в GitHub: $latest_commit\nПоследняя версия ядра Linux: $latest_kernel\nВаша версия ядра: $(uname -r)\nАрхитектура ЦП: $archType\nАппаратное ускорение включено: $hardwareAcceleration\nАппаратный рендерер: $hardwareRenderer\n-------------------------------------\nПожалуйста, выберите опцию:\n1. Техническая настройка\n2. Настройка цели\n3. Установка рабочего окружения\n4. Установка графических драйверов\n5. Установка последнего релиза ProtonGE\n6. Демо-дистрибутив\n7. Выход"
tech_setup_es_ES="-------------------------------------\nScript de Configuración\n-------------------------------------\nVersión:1.1\nDistribución Detectada: $DISTRIBUTION $VERSION_ID\nÚltimo Commit de GitHub: $latest_commit\nÚltima Versión del Kernel de Linux: $latest_kernel\nVersión de tu Kernel: $(uname -r)\nArquitectura de la CPU: $archType\nAceleración de Hardware habilitada: $hardwareAcceleration\nRenderizador de Hardware: $hardwareRenderer\n-------------------------------------\nPor favor, seleccione una opción:\n1. Configuración Técnica\n2. Configuración de Propósito\n3. Instalar un Entorno de Escritorio\n4. Instalar controladores gráficos\n5. Instalar la última versión de ProtonGE\n6. Demostración del Distro\n7. Salir"
tech_setup_fi_FI="-------------------------------------\nAsennusskripti\n-------------------------------------\nVersio:1.1\nTunnistettu jakelu: $DISTRIBUTION $VERSION_ID\nViimeisin GitHubin sitoutuminen: $latest_commit\nViimeisin Linux-ytimen versio: $latest_kernel\nKäyttämäsi ytimen versio: $(uname -r)\nSuorittimen arkkitehtuuri: $archType\nLaitteistokiihdytys käytössä: $hardwareAcceleration\nLaitteiston renderöinti: $hardwareRenderer\n-------------------------------------\nValitse vaihtoehto:\n1. Tekninen asennus\n2. Tarkoitusasennus\n3. Työpöytäympäristön asentaminen\n4. Grafiikka-ajureiden asentaminen\n5. Viimeisimmän ProtonGE-julkaisun asentaminen\n6. Distro-esittely\n7. Poistu"
tech_setup_zh_CN="-------------------------------------\n安装脚本\n-------------------------------------\n版本：1.1\n检测到的发行版：$DISTRIBUTION $VERSION_ID\n最新的GitHub提交：$latest_commit\n最新的Linux内核版本：$latest_kernel\n您的内核版本：$(uname -r)\nCPU架构：$archType\n硬件加速启用：$hardwareAcceleration\n硬件渲染器：$hardwareRenderer\n-------------------------------------\n请选择一个选项：\n1. 技术设置\n2. 目的设置\n3. 安装桌面环境\n4. 安装图形驱动程序\n5. 安装最新的ProtonGE版本\n6. 发行版演示\n7. 退出"
tech_setup_ko_KR="-------------------------------------\n설정 스크립트\n-------------------------------------\n버전:1.1\n감지된 배포판: $DISTRIBUTION $VERSION_ID\n최근 GitHub 커밋: $latest_commit\n최신 Linux 커널 버전: $latest_kernel\n사용 중인 커널 버전: $(uname -r)\nCPU 아키텍처: $archType\n하드웨어 가속 활성화됨: $hardwareAcceleration\n하드웨어 렌더러: $hardwareRenderer\n-------------------------------------\n옵션을 선택하세요:\n1. 기술 설정\n2. 목적 설정\n3. 데스크톱 환경 설치\n4. 그래픽 드라이버 설치\n5. 최신 ProtonGE 릴리스 설치\n6. 배포판 데모\n7. 종료"
tech_setup_he_IL="-------------------------------------\n סקריפט התקנה\n-------------------------------------\nגרסה:1.1\nהפצה מזוהה: $DISTRIBUTION $VERSION_ID\nהתחייבות GitHub אחרונה: $latest_commit\nגרסת הליבה האחרונה של Linux: $latest_kernel\nגרסת הליבה שלך: $(uname -r)\nארכיטקטורת ה-CPU: $archType\nהאצת חומרה מופעלת: $hardwareAcceleration\nמנדף חומרה: $hardwareRenderer\n-------------------------------------\nאנא בחר אופציה:\n1. הגדרה טכנית\n2. הגדרת מטרה\n3. התקנת סביבת שולחן עבודה\n4. התקנת מנהלי התקנים גרפיים\n5. התקנת גרסת ProtonGE האחרונה\n6. הדגמת הפצה\n7. יציאה"
purpose_setup_en_US="-------------------------------------\nPlease select a purpose for your distro\n-------------------------------------\n1. Basic\n2. Gaming\n3. Corporate\n4. Development\n5. Astronomy\n6. Comp-Neuro\n7. Desing\n8. Jam\n9. Security Lab\n10. Robotics\n11. Scientific\n12. Offline"
purpose_setup_ja_JP="ディストリビューションの目的を選択してください:\n1. ベーシック\n2. ゲーミング\n3. コーポレート\n4. 開発\n5. 天文学\n6. コンプ-ニューロ\n7. デザイン\n8. ジャム\n9. セキュリティラボ\n10. ロボティクス\n11. 科学的\n12. オフライン"
purpose_setup_ru_RU="Выберите цель для вашего дистрибутива:\n1. Базовый\n2. Игровой\n3. Корпоративный\n4. Разработка\n5. Астрономия\n6. Комп-Нейро\n7. Дизайн\n8. Джем\n9. Лаборатория безопасности\n10. Робототехника\n11. Научный\n12. Оффлайн"
purpose_setup_es_ES="Por favor seleccione un propósito para su distro:\n1. Básico\n2. Juegos\n3. Corporativo\n4. Desarrollo\n5. Astronomía\n6. Neuro-Comp\n7. Diseño\n8. Jam\n9. Laboratorio de Seguridad\n10. Robótica\n11. Científico\n12. Sin conexión"
purpose_setup_fi_FI="-------------------------------------\nValitse tarkoitus jakelullesi\n-------------------------------------\n1. Perus\n2. Pelaaminen\n3. Yrityskäyttö\n4. Kehitys\n5. Tähtitiede\n6. Aivotutkimus\n7. Suunnittelu\n8. Musiikki\n9. Turvallisuuslaboratorio\n10. Robotiikka\n11. Tieteellinen\n12. Offline"
purpose_setup_zh_CN="请选择您的发行版目的:\n1. 基础\n2. 游戏\n3. 企业\n4. 开发\n5. 天文学\n6. 计算神经科学\n7. 设计\n8. 果酱\n9. 安全实验室\n10. 机器人技术\n11. 科学\n12. 离线"
purpose_setup_ko_KR="디스트리뷰션의 목적을 선택해 주세요:\n1. 기본\n2. 게이밍\n3. 기업\n4. 개발\n5. 천문학\n6. 컴퓨터 신경과학\n7. 디자인\n8. 잼\n9. 보안 실험실\n10. 로보틱스\n11. 과학\n12. 오프라인"
purpose_setup_he_IL="בחרו את המטרה עבור ההפצה שלכם:\n1. בסיסי\n2. משחקים\n3. תאגידי\n4. פיתוח\n5. אסטרונומיה\n6. נוירו-מחשב\n7. עיצוב\n8. ג'אם\n9. מעבדת אבטחה\n10. רובוטיקה\n11. מדעי\n12. לא מקוון"

# Declaring Global Functions
# Message Functions
info() { echo -e "${BLUE}$1${ENDCOLOR}"; }
error() { echo -e "${RED}$1${ENDCOLOR}"; }
caution() { echo -e "${YELLOW}$1${ENDCOLOR}"; }
success() { echo -e "${GREEN}$1${ENDCOLOR}"; }
# Declaring Specific Functions
identifyDistro ()
{
if [[ -f /etc/os-release ]]; then
        source /etc/os-release 
        if [[ -n "$NAME" ]]; then
            export DISTRIBUTION=$NAME
            export VERSION=$VERSION_ID
        fi
    elif [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        if [[ -n "$DISTRIB_ID" ]]; then
            export DISTRIBUTION=$DISTRIB_ID
            export VERSION=$DISTRIB_RELEASE
        fi
    else
        export DISTRIBUTION="Unknown"
        export VERSION="Unknown"
    fi
    case $NAME in
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*)
    pkgm=dnf
    pkgext=rpm
    argInstall=install
    argUpdate=update
    preFlags=""
    postFlags="--allowerasing --skip-broken -y"
    essentialPackages="$essentialPackages $essentialPackagesRPM"
    amdPackages="$amdPackages $amdPackagesRPM"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesRPM"
    virtconPackages="$virtconPackages $virtconPackagesRPM"
    desktopOption=2
    grubPath="/etc/default/grub"
    grubUpdate="grub2-mkconfig -o /boot/grub2/grub.cfg"
    flatpakRepo="fedora"
    ;;
    *Red*)
    caution "RHEL"
    pkgm=dnf
    pkgext=rpm
    argInstall=install
    argUpdate=update
    preFlags=""
    postFlags="--skip-broken -y"
    essentialPackages="$essentialPackages $essentialPackagesRPM"
    amdPackages="$amdPackages $rhelPackages $amdPackagesRPM"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesRPM"
    virtconPackages="$virtconPackages $virtconPackagesRPM"
    desktopOption="3,4"
    grubPath="/etc/default/grub"
    grubUpdate="grub2-mkconfig -o /boot/grub2/grub.cfg"
    ;;
    *CentOS*)
    caution "CentOS"
    pkgm=dnf
    pkgext=rpm
    argInstall=install
    argUpdate=update
    preFlags=""
    postFlags="--skip-broken -y"
    essentialPackages="$essentialPackages $essentialPackagesRPM"
    amdPackages="$amdPackages $amdPackagesRPM"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesRPM"
    virtconPackages="$virtconPackages $virtconPackagesRPM"
    desktopOption=2
    grubPath="/etc/default/grub"
    grubUpdate="grub2-mkconfig -o /boot/grub2/grub.cfg"

    ;;
    *Debian*|*Ubuntu*|*Kubuntu*|*Lubuntu*|*Xubuntu*|*Uwuntu*|*Linuxmint*|*Pop!_OS*)
    pkgm=apt
    pkgext=deb
    argInstall=install
    argUpdate=update
    preFlags="-f"
    postFlags="-y -m"
    essentialPackages="$essentialPackages $essentialPackagesDebian"
    basicSystemPackages="$basicSystemPackages $basicSystemPackagesDebian"
    amdPackages="$amdPackages $amdPackagesDebian"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesDebian"
    virtconPackages="$virtconPackages $virtconPackagesDebian"
    desktopOption=1
    grubPath="/etc/default/grub"
    grubUpdate="update-grub"
    ;;
    *Gentoo*)
    caution "Gentoo is not supported, and you wouldn't be using scripts anyway."
    ;;
    *Slackware*)
    caution "Slackware is not supported."
    ;;
    *Arch*)
    caution "Arch is not supported, and you wouldn't be using scripts anyway."
    ;;
    *openSUSE*)
    caution "openSUSE is being tested."
    pkgm=zypper
    pkgext=rpm
    argInstall=install
    argUpdate=refresh
    preFlags=""
    postFlags="--force --non-interactive"
    essentialPackages="$essentialPackages $essentialPackagesOpenSUSE"
    basicSystemPackages="$basicSystemPackages"
    amdPackages="$amdPackages $amdPackagesOpenSUSE"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesOpenSUSE"
    virtconPackages="$virtconPackages $virtconPackagesOpenSUSE"
    desktopOption=5
    grubPath="/etc/default/grub"
    grubUpdate="grub2-mkconfig -o /boot/grub2/grub.cfg"
    ;;
    *)
    echo "2"
    ;;
    esac
    displayMenu
}
load_dictionary() {
    case "$locale_language" in
        *en_US* | *en* | *en_*)
            printingDisplay="${phase}_en_US"
            info "${!printingDisplay}"
            ;;
        *es_ES* | *es_ES* | es | es_)
            printingDisplay="${phase}_es_ES"
            info "${!printingDisplay}"
            ;;
	    *ru_RU* | *ru_RU* | ru | ru_)
            printingDisplay="${phase}_ru_RU"
            info "${!printingDisplay}"
            ;;
	    *ja_JP* | *ja_JP* | *ja* | *ja_*)
            printingDisplay="${phase}_ja_JP"
            info "${!printingDisplay}"
            ;;
	    *fi_FI* | *fi* | *fi_*)
            printingDisplay="${phase}_fi_FI"
            info "${!printingDisplay}"
            ;;
	    *zh_CN* | *zh* | *zh_*)
            printingDisplay="${phase}_zh_CN"
            info "${!printingDisplay}"
            ;;
	    *ko_KR* | *ko* | *ko_*)
            printingDisplay="${phase}_ko_KR"
            info "${!printingDisplay}"
            ;;
	    *he_IL* | *he* | *he_*)
            printingDisplay="${phase}_he_IL"
            info "${!printingDisplay}"
            ;;
	    *)
            caution "Locale not supported. Using default English (en) dictionary."
            printingDisplay="${phase}_en_US"
            info "${!printingDisplay}"
            ;;
    esac
}
displayMenu ()
{
  clear
  phase=tech_setup
  load_dictionary
  read optionmenu
  case $optionmenu in
    1)
        clear
        caution "Tech Setup is starting..."
        techSetup
        ;;
    2)
        purposeMenu
        ;;
    3)
        desktopenvironmentMenu
        finalTweaks
        ;;
    4)
        graphicDrivers
        ;;
    5)
        installproton
        ;;
    6)
        caution "Running distro demo, still on the works"
        distroDemo
        ;;
    7)
        caution "Exit"
        ;;
    0)
        caution "Server Setup Runs"
        serverSetup
        ;;
    
    *)
        error "Bad input"
        ;;
    esac
}
desktopenvironment ()
{
    if [[ -n $XDG_CURRENT_DESKTOP ]]; then
        success "You have $XDG_CURRENT_DESKTOP installed already, moving on"
    else
        desktopenvironmentMenu
        success "You have $XDG_CURRENT_DESKTOP installed, moving on"
    fi
}
desktopenvironmentMenu ()
{
  caution "What Desktop Environment you want?\n1. GNOME\n2. XFCE\n3. KDE\n4. LXQT\n5. CINNAMON\n6. MATE\n7. i3\n8. OPENBOX\n9. BUDGIE\n10. SWAY\n11. HYPRLAND\n12.NONE"
  read option
  case $option in
    1)
        gnomePackages="$(echo "$gnomePackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $gnomePackages $postFlags && sudo systemctl set-default graphical.target
        success "You have GNOME installed, moving on"
        ;;
    2)
        xfcePackages="$(echo "$xfcePackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $xfcePackages $basicDesktopEnvironmentPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have XFCE installed, moving on"
        ;;
    3)
        kdePackages="$(echo "$kdePackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $kdePackages $postFlags && sudo systemctl set-default graphical.target
        success "You have KDE installed, moving on"
        ;;
    4)
        lxqtPackages="$(echo "$lxqtPackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $lxqtPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have LXQT installed, moving on"
        ;;
    5)
        cinnamonPackages="$(echo "$cinnamonPackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $cinnamonPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have CINNAMON installed, moving on"
        ;;
    6)
        matePackages="$(echo "$matePackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $matePackages $postFlags && sudo systemctl set-default graphical.target
        success "You have MATE installed, moving on"
        ;;
    7)
        i3Packages="$(echo "$i3Packages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $i3Packages $i3RicingPackages $basicDesktopEnvironmentPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have i3 installed, moving on"
        ;;
    8)
        openboxPackages="$(echo "$openboxPackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $openboxPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have OPENBOX installed, moving on"
        ;;
    9)
        budgiePackages="$(echo "$budgiePackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $budgiePackages $postFlags && sudo systemctl set-default graphical.target
        success "You have BUDGIE installed, moving on"
        ;;
    10)
        swayPackages="$(echo "$swayPackages" | awk '{print $desktopOption}')"
        sudo $pkgm $argInstall $swayPackages $basicDesktopEnvironmentPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have SWAY installed, moving on"
        ;;
    11)
        info "Still on the works"
        sudo $pkgm $argInstall $basicDesktopEnvironmentPackages $hyprlandPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have HYPRLAND installed, moving on"
        ;;
    12)
        info "Still on the works"
        niriRepo
        sudo $pkgm $argInstall $basicDesktopEnvironmentPackages $niriPackages $postFlags && sudo systemctl set-default graphical.target
        success "You have NIRI installed, moving on"
        ;;
    13)
        caution "No Desktop Environment will be installed"
        ;;
    *)
        error "Wrong choice. Exiting script."
        exit
        ;;
    esac
}
graphicDrivers ()
{
    info "Installing GPU drivers"

    if lspci | grep 'NVIDIA' > /dev/null; then
        if nvidia-smi > /dev/null 2>&1; then
            success "NVIDIA drivers are installed already."
        else
            caution "NVIDIA card detected. Would you like to install NVIDIA packages? (y/n)"
            read -r option
            if [ "$option" == "y" ]; then
                info "Installing NVIDIA drivers and CUDA support"
                sudo $pkgm $argInstall $nvidiaPackages $cudaPackages $postFlags
            else
                caution "NVIDIA packages will not be installed."
            fi
        fi
    elif lspci | grep -E 'Radeon|AMD' > /dev/null; then
        if lsmod | grep amdgpu > /dev/null 2>&1; then
            success "AMD drivers are installed already."
        else
            caution "AMD GPU detected. Would you like to install ROCm/HIP packages? (y/n)"
            read -r option
            if [ "$option" == "y" ]; then
                info "Installing AMD drivers and ROCm/HIP support"
                sudo $pkgm $argInstall $amdPackages $postFlags
            else
                caution "AMD drivers without ROCm will be installed."
                sudo $pkgm $argInstall $amdPackages $postFlags
            fi
        fi
    elif lspci | grep -E 'Intel' > /dev/null; then
        caution "Intel GPU detected. Would you like to install oneAPI packages? (y/n)"
        read -r option
        if [ "$option" == "y" ]; then
            info "Installing Intel drivers and oneAPI support"
            sudo $pkgm $argInstall $intelPackages $postFlags
        else
            caution "Installing basic Intel GPU drivers."
            sudo $pkgm $argInstall $intelPackages $postFlags
        fi
    #elif lspci | grep -E 'ASPEED' > /dev/null; then
    #    caution "ASPEED GPU detected. Installing ASPEED drivers."
    #    sudo $pkgm $argInstall xserver-xorg-video-ast ipmitool $postFlags
    #    sudo modprobe ast
    #    fi
    #else lspci | grep -E 'Matrox' > /dev/null; then
    #    caution "Matrox GPU detected. Installing Matrox drivers."
    #    sudo $pkgm $argInstall xserver-xorg-video-mga $postFlags
    #    sudo modprobe mgag200
    #    fi
    else
        caution "No dedicated GPU found or unrecognized GPU. Moving on."
    fi
}
flathubEnable ()
{
    info "Enabling Flathub repository for Flatpak"
    case $NAME in
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*)
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    ;;
    *Red*)
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    ;;
    *Debian*|*Ubuntu*|*Kubuntu*|*Lubuntu*|*Xubuntu*|*Uwuntu*|*Linuxmint*|*Pop!_OS*)
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    ;;
    *)
    ;;
    esac
    flatpakRepo="flathub"
}
updateGrub ()
{
    sudo sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/' $grubPath
    sudo $grubUpdate
}
installSVP() {
    local svpName="svp4-linux"
    local svpVersion=".4.6.263"
    local url="https://www.svp-team.com/files/$svpName$svpVersion.tar.bz2"

    if which /home/$USER/SVP\ 4/SVPManager > /dev/null 2>&1;
    then
        echo "SVP is already installed"
    else
        wget "$url"
        bunzip2 $svpName$svpVersion.tar.bz2
        tar -xf $svpName$svpVersion.tar &
        wait $!
        sudo chmod +x $svpName-64.run
        sudo -u $USER ./$svpName-64.run && rm svp4-latest* $svpName-64.run 
    fi
}
sharedFolder ()
{
  #Mounting Windows Shared folder
        echo "Do you want to setup a Windows Shared Folder?"
        read option
        if [ $option == y ]
        then
            echo "What is the server name you wish to connect to?"
            read server
            echo "What is the shared folder of $server?"
            read folder
            echo "What is the user to connect to $folder in $server?"
            read srvuser2o mount.cifs //$server/$folder /home/$(whoami)/WinFiles/ -o user=$srvuser
            echo "Windows Shared Folder has been successfully mounted!"
        else
            info "No Windows shared folders were added\n--------------------------------------"
        fi
}
installproton() {
  COMPATIBILITY_DIR="$HOME/.steam/root/compatibilitytools.d"
  LATEST_VERSION=21

  if [ -d "$COMPATIBILITY_DIR" ]; then
    CURRENT_VERSION=$(ls "$COMPATIBILITY_DIR" | grep -Eo '[0-9]+' | sort -nr | head -n 1)
    if [ "$CURRENT_VERSION" -eq "$LATEST_VERSION" ]; then
      success "You already have the latest ProtonGE $CURRENT_VERSION version."
      return
    fi
  else
    mkdir -p "$COMPATIBILITY_DIR"
  fi

  for VERSION in {28..21}; do
    if [ "$CURRENT_VERSION" -eq "$VERSION" ]; then
      continue
    fi

    wget -q "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-$VERSION/GE-Proton9-$VERSION.tar.gz"
    if [ $? -eq 0 ]; then
      info "Installing version $VERSION..."
      tar -xf "GE-Proton9-$VERSION.tar.gz" -C "$COMPATIBILITY_DIR" && rm "GE-Proton9-$VERSION.tar.gz"
      wait $!
      success "ProtonGE $VERSION has been installed."
      break
    else
      caution "Version $VERSION not found (yet)."
    fi
  done
}
#Removed in favour of Flatpak
#microsoftRepo
#microsoftPackagesArray=($microsoftPackages)
#microsoftPackages=$(echo "${microsoftPackagesArray[0]}")
#microsoftRepo ()
#{
#    case $NAME in 
#    *Fedora*|*Nobara*|*Risi*|*Ultramarine*)
#    addMicrosoft="sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc"
#    enableMicrosoft="sudo $pkgm config-manager --add-repo https://packages.microsoft.com/yumrepos/edge && sudo mv /etc/yum.repos.d/packages.microsoft.com_yumrepos_edge.repo /etc/yum.repos.d/microsoft-edge-stable.repo && sudo $pkgm config-manager --add-repo https://packages.microsoft.com/yumrepos/vscode && curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo"
#    $addMicrosoft && $enableMicrosoft
#    ;;
#    *Debian*|*Ubuntu*|*Kubuntu*|*Lubuntu*|*Xubuntu*|*Uwuntu*|*Linuxmint*|*Pop!_OS*)
#    if [[ "$NAME" == "Debian" ]]; then
#            addMicrosoft="curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -"
#            else
#            addMicrosoft="curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc"
#            fi
#    $addMicrosoft
#    ;;
#    esac
#}
niriRepo ()
{
    case $NAME in 
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*)
        sudo $pkgm copr enable yalter/niri -y
    ;;
    *Debian*|*Ubuntu*|*Kubuntu*|*Lubuntu*|*Xubuntu*|*Uwuntu*|*Linuxmint*|*Pop!_OS*)
        caution "Still not supported."
    ;;
    *)
        info "Not supported." 
    ;;
    esac
}
anydeskRepo ()
{
    case $NAME in 
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*)
        sudo cat > /etc/yum.repos.d/AnyDesk-Fedora.repo << "EOF" 
[anydesk]
name=AnyDesk Fedora - stable
baseurl=http://rpm.anydesk.com/fedora/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF
    ;;
    *Red*)
    sudo cat > /etc/yum.repos.d/AnyDesk-RHEL.repo << "EOF"
[anydesk]
name=AnyDesk RHEL - stable
baseurl=http://rpm.anydesk.com/rhel/$releasever/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF
    ;;
    *CentOS*)
    sudo cat > /etc/yum.repos.d/AnyDesk-CentOS.repo << "EOF"
[anydesk]
name=AnyDesk CentOS - stable
baseurl=http://rpm.anydesk.com/centos/$releasever/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF
    ;;

    *openSUSE*)
    cat > AnyDesk-OpenSUSE.repo << "EOF" 
[anydesk]
name=AnyDesk OpenSUSE - stable
baseurl=http://rpm.anydesk.com/opensuse/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF

$pkgm addrepo --repo AnyDesk-OpenSUSE.repo
    ;;
    *Debian*|*Ubuntu*|*Kubuntu*|*Lubuntu*|*Xubuntu*|*Uwuntu*|*Linuxmint*|*Pop!_OS*)
        wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
        echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
        sudo $pkgm $argUpdate
    ;;
    *)
    caution "Not supported for other distros yet."
    ;;
    esac
}
librewolfRepo ()
{
    case $NAME in 
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*)
        sudo $pkgm config-manager --add-repo https://repo.librewolf.net/librewolf.repo $postFlags
        sudo $pkgm $argInstall librewolf $postFlags
    ;;
    *Debian*|*Ubuntu*|*Kubuntu*|*Lubuntu*|*Xubuntu*|*Uwuntu*|*Linuxmint*|*Pop!_OS*)
        sudo $pkgm $argUpdate update && sudo $pkgm $argInstall extrepo $postFlags
        sudo extrepo enable librewolf
        sudo $pkgm $argUpdate && sudo $pkgm $argInstall librewolf $postFlags
    ;;
    *)
    caution "Not supported for other distros yet."
    ;;
    esac
}
askReboot ()
{
  caution "Would you like to reboot? (Recommended) [y/N]"
  read option
    if [ $option == y ]
    then
        sudo reboot
    else
        caution "No reboot was requested."
    fi
}
distroboxContainers ()
{
    distrobox-create --name fedora --image quay.io/fedora/fedora:latest -Y
    #distrobox-create --name ubuntu --image docker.io/library/ubuntu:latest -Y
    #distrobox-create --name rhel --image registry.access.redhat.com/ubi9/ubi -Y
    distrobox-create --name debian --image docker.io/library/debian:latest -Y
    #distrobox-create --name clearlinux --image docker.io/library/clearlinux:latest -Y
    #distrobox-create --name centos --image quay.io/centos/centos:stream9 -Y
    #distrobox-create --name arch --image docker.io/library/archlinux:latest -Y
    #distrobox-create --name opensusel --image registry.opensuse.org/opensuse/leap:latest -Y
    #distrobox-create --name opensuset --image registry.opensuse.org/opensuse/tumbleweed:latest  -Y
    #distrobox-create --name gentoo --image docker.io/gentoo/stage3:latest -Y
}
distroDemo ()
{
    info "this is a great demo of the distro you want to use\nThe current environment you use is the following:\n"
    ssh -V
}
purposeMenu ()
{
  phase=purpose_setup
  clear
  load_dictionary
  read optionmenu
  case $optionmenu in
    #Basic
    1) 
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Gaming
    2)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $gamingPackages $postFlags
        installproton
        ;;
    #Corporate
    3)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $ciscoPackages $postFlags
        sudo flatpak install $flatpakRepo $googleFlatpak $microsoftFlatpak $remoteSupportFlatpak -y
        ;;
    #Corporate (just Microsoft)
    4)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        sudo flatpak install $flatpakRepo $microsoftFlatpak $remoteSupportFlatpak -y
        ;;
    #Corporate (just Google)
    5)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        sudo flatpak install $flatpakRepo $googleFlatpak $remoteSupportFlatpak -y
        ;;
    #Development
    6)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $developmentPackages $virtconPackages $postFlags
        distroboxContainers
        ;;
    #Astronomy
    7)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Comp-Neuro
    8)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Design
    9)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Music Production
    10)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Cybersecurity
    11)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Forensics
    12)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Scientific
    13)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #Robotics
    14)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlags
        ;;
    #
    15)
        displayMenu
        ;;
    0)
        caution $1
        sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $gamingPackages $multimediaPackages $developmentPackages $virtconPackages $amdPackagesRPM $supportPackages $ciscoPackages $languagePackages $postFlags
        installSVP #Trying to find a FOSS alternative for smooth video
        distroboxContainers
        sudo usermod -aG libvirt $(whoami)
        #xdg-settings set default-web-browser microsoft-edge.desktop
        ;;
    *)
        # Code to execute when $variable doesn't match any of the specified values
        ;;
    esac
    displayMenu
}
serverSetup ()
{
    sudo $pkgm update -y && sudo $pkgm upgrade -y
    sudo $pkgm $argInstall $preFlags $essentialPackages $basicSystemPackages $serverPackages $developmentPackages $postFlags
}
techSetup ()
{
    caution $NAME
    case $NAME in
    *Fedora*)
    #DNF5 works fine, will drop dnf.conf related configs
    #if [ $(cat /etc/dnf/dnf.conf | grep fastestmirror=true) ]
    #  then
    #      echo ""
    #  else
    #      sudo sh -c 'echo fastestmirror=true >> /etc/dnf/dnf.conf' #Looks for the lowest ping, not necessarily the best bandwith
    #      sudo sh -c 'echo max_parallel_downloads=10 >> /etc/dnf/dnf.conf'
    #  fi 
    sudo systemctl disable NetworkManager-wait-online.service
    caution "Installing RPM FUsion"
    if [ -f /etc/yum.repos.d/rpmfusion-free.repo ] || [ -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]; then
        caution "RPM Fusion is installed already, moving on"
        else
        sudo $pkgm $argInstall https://mirror.fcix.net/rpmfusion/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://opencolo.mm.fcix.net/rpmfusion/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm fedora-workstation-repositories dnf-plugins-core -y && sudo $pkgm update -y && sudo $pkgm install $essentialPackages -y
        updateGrub
    fi
    ;;
    *Nobara*|*Risi*|*Ultramarine*)
    sudo $pkgm $argUpdate -y && sudo $pkgm install $essentialPackages -y
    updateGrub
    ;;
    *Red*)
    caution "RHEL"
    sudo systemctl disable NetworkManager-wait-online.service
    info "Installing EPEL repo"
    sudo subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
    sudo $pkgm $argInstall https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -y
    info "Installing Essential Packages"
    sudo $pkgm $argInstall $essentialPackages $postFlags
    ;;
    *Debian*|*Ubuntu*|*Kubuntu*|*Lubuntu*|*Xubuntu*|*Uwuntu*|*Linuxmint*|*Pop!_OS*)
    sudo $pkgm $argUpdate -y && sudo $pkgm upgrade -y
    sudo $pkgm $argInstall $essentialPackages -y
    ;;
    *Gentoo*)
    caution "Gentoo"
    ;;
    *Slackware*)
    caution "Slackware"
    ;;
    *Arch*)
    caution "Arch"
    ;;
    *openSUSE*)
    caution "openSUSE"
    sudo $pkgm $argUpdate $postFlags && sudo $pkgm update $postFlags
    info "Installing Essential Packages"
    sudo $pkgm $argInstall $essentialPackages $postFlags
    ;;
    *)
    echo "2"
    ;;
    esac
    flathubEnable
    desktopenvironment
    graphicDrivers
    #nvtopInstall
    finalTweaks
    askReboot
    displayMenu
}
#This functios in only for Fedora, might be adapted to other distros like openSUSE
swapCodecsFedora ()
{
    pkg1=$(echo $essentialPackages | awk '{print $7}')
    pkg2=$(echo $fedoraPackages | awk '{print $1}')
    pkg3=$(echo $fedoraPackages | awk '{print $3}')
    sudo $pkgm swap $preFlags $pkg1 $pkg2 $postFlags
    pkg1=$(echo $essentialPackages | awk '{print $8}')
    pkg2=$(echo $fedoraPackages | awk '{print $2}')
    sudo $pkgm swap $preFlags $pkg1 $pkg2 $postFlags
    sudo $pkgm $argInstall $preFlags $pkg3 $postFlags
}
finalTweaks ()
{
  # Hostname
  #if [[ $(hostname) == $hostnamegiven ]];
  #then
  #    echo "Please provide a hostname for the computer"
  #    read hostname
  #    sudo hostnamectl set-hostname --static $hostname
  #else
  #    echo 'hostname was not changed'
  #fi
  # Aesthetic Tweaks
  #sudo $pkgm $argInstall $preFlags plymouth plymouth-theme-spinfinity $postFlags
  #sudo plymouth-set-default-theme spinfinity -R
  # Desktop Environment tweaks
  case $XDG_SESSION_DESKTOP in
    *gnome*|*xfce*)
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true  
    gsettings set org.gnome.desktop.session idle-delay 0
    xdg-mime default thunar.desktop inode/directory
    ;;
    *hyprland*|*Hyprland*)
    #caution "Getting hyprland.conf"
    #unzip main.zip
    #if [ -d "/home/$(whoami)/.config/profiles/wofi" ]; then
    #    echo "Not installing custom config files for hyprland"
    #else
    #    rm -rf ~/.config/hypr/
    #    rm -rf ~/.config/wofi/
    #    rm -rf ~/.config/waybar/
    #    mv Carino-Systems-main/profiles/wofi /home/$(whoami)/.config/
    #    mv Carino-Systems-main/profiles/hypr /home/$(whoami)/.config/
    #    mv Carino-Systems-main/profiles/waybar /home/$(whoami)/.config/
    #    rm -rf main.zip Carino-Systems-main main.zip
    #fi
    caution "Other things"
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    xdg-mime default thunar.desktop inode/directory
    ;;
    *i3*)
    git clone https://gitlab.com/dajhub/i3-dotfiles.git
    cp -r ~/i3-dotfiles/.config/i3/ ~/.config/
    cp -r ~/i3-dotfiles/.fonts/ ~/
    cp -r ~/i3-dotfiles/.icons/ ~/
    #curl -s https://raw.githubusercontent.com/MiguelCarino/Carino-Systems/main/profiles/i3/config > ~/.config/i3/config
    # xinput set-prop "ASUE1200:00 04F3:30F7 Touchpad" "libinput Tapping Enabled" 1
    
    ;;
    *)
    error "No supported Desktop Environment for tweaks"
    ;;
    esac
}
updateSystem ()
{
  sudo $pkgm $argUpdate -y
  success "Your system has been updated"
}
# Declaring Packages
# Generic GNU/Linux Packages
#Essential packages are what will allow system review for advanced users and stable hardware experience
essentialPackages="pciutils git cmake wget nano curl jq mesa-va-drivers mesa-vdpau-drivers elinks nasm ncurses-dev* lshw lm*sensors rsync rclone mediainfo cifs-utils ntfs-3g* lsof xinput flatpak" #gcc-c++ lm_sensors.x86_64
#Server packages ensure SSH, FTP and RDP connectivity, so advanced users can configure and use the server remotely
serverPackages="netcat-traditional xserver-xorg-video-dummy openssh-server cockpit expect ftp vsftpd sshpass"
#Basic packages will allow endusers to perform basic activities or get basic features
basicUserPackages="gedit yt-dlp thunderbird mpv ffmpeg ffmpegthumbnailer tumbler clamav clamtk libreoffice obs-studio epiphany transmission pavucontrol vnstat feh" #fontawesome-fonts-all
basicSystemPackages="wine xrdp htop powertop tldr *gtkglext* libxdo-* ncdu scrot xclip"
basicSystemPackagesOpenSUSE=""
basicDesktopEnvironmentPackages="nautilus fontawesome-fonts"
#Gaming packages will allow enduseres to play on the most popular platforms
gamingPackages="steam goverlay lutris"
#Multimedia pacakges allow the end user to use the most
multimediaPackages="gimp krita blender kdenlive gstreamer* gscan2pdf python3-qt* python3-vapoursynth qt5-qtbase-devel vapoursynth-* libqt5* libass*" #qt5-qtbase-devel python3-qt5
developmentPackages="gcc cargo npm python3-pip nodejs golang conda*"
virtconPackages="podman distrobox bridge-utils virt-manager virt-top"
virtconPackagesRPM="@virtualization libvirt libvirt-devel virt-install qemu-kvm qemu-img"
virtconPackagesDebian="libvirt-daemon-system libvirt-clients virtinst"
virtconPackagesOpenSUSE=""
supportPackages="remmina keepassxc bless xxd" #stacer barrier bleachbit filezilla
amdPackages="ocl-icd-dev* opencl-headers libdrm-dev* rocm*"
nvidiaPackages="vdpauinfo libva-utils vulkan nvidia-xconfig xorg-x11-drv-nvidia-cuda libva-vdpau-driver" #libva-vdpau-driver kernel-headers kernel-devel xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs
nvidiaPackagesRPM="akmod-nvidia nvidia-vaapi-driver"
nvidiaPackagesDebian="nvidia-driver* nvidia-opencl* nvidia-xconfig nvidia-vdpau-driver nvidia-vulkan*"
nvidiaPackagesUbuntu="nvidia-driver-560"
nvidiaPackagesOpenSUSE=""
xfcePackages="task-xfce-desktop @xfce-desktop-environment patterns-openSUSE-xfce @Xfce @base-x"
gnomePackages="task-gnome-desktop @workstation-product-environment patterns-openSUSE-gnome @gnome @base-x gnome-extensions"
kdePackages="task-kde-desktop @kde-desktop-environment patterns-kde-kde @kde @base-x patterns-openSUSE-kde"
lxqtPackages="task-lxqt-desktop @lxqt-desktop-environment patterns-lxqt-lxqt"
cinnamonPackages="task-cinnamon-desktop @cinnamon-desktop-environment patterns-cinnamon-cinnamon"
matePackages="task-mate-desktop @mate-desktop-environment patterns-mate-mate"
i3Packages="i3 @i3-desktop-environment $i3openSUSE"
i3openSUSE="i3 dmenu i3status"
i3RicingPackages="rofi i3blocks picom kitty nitrogen lxappearance"
openboxPackages="openbox @basic-desktop-environment @openbox @base-x"
budgiePackages="budgie-desktop budgie-desktop budgie-desktop @budgie @base-x"
swayPackages="sway sway @sway @base-x"
hyprlandPackages="hyprland xorg-x11-server-Xwayland waybar xdg-desktop-portal-hyprland hyprland-autoname-workspaces hyprpaper libdisplay-info libinput libliftoff hyprshot" #Still on the works
niriPackages="niri waybar" #Still on the works
# Specific GNU/Linux Packages
intelPackages="intel-media-*driver"
basicSystemPackagesDebian="neofetch"
essentialPackagesRPM="NetworkManager-tui xkill tigervnc-server dhcp-server fastfetch"
essentialPackagesDebian="software-properties-common build-essential manpages-dev net-tools x11-utils tigervnc-standalone-server tigervnc-common tightvncserver isc-dhcp-server" #libncurses5-dev libncursesw5-dev libgtkglext1 linux-headers-amd64 linux-image-amd64
essentialPackagesOpenSUSE=""
amdPackagesRPM="xorg-x11-drv-amdgpu systemd-devel" #xorg-x11-dr*
amdPackagesDebian="xserver-xorg-video-amdgpu libsystemd-dev"
amdPackagesOpenSUSE=""
fedoraPackages="mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld libavcodec-freeworld dnf-plugin-system-upgrade"
rhelPackages="mesa-dri-drivers libavcodec*" #mesa-vdpau-drivers
astronomyPackages="astropy kstars celestia siril "
compneuroPackages="neuron "
# Corporate Packages
#remoteSupportPackages="anydesk"
rustdesk="https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-0.x86_64.rpm https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-x86_64.deb" #Taken from https://github.com/rustdesk/rustdesk/releases/
microsoftPackages="microsoft-edge-stable code" #powershell
zoom="https://zoom.us/client/latest/zoom_x86_64.rpm"
#googlePackages="https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"
ciscoPackages="https://binaries.webex.com/WebexDesktop-CentOS-Official-Package/Webex.rpm vpnc"
# CustomPackages
languagePackages="fcitx5 fcitx5-mozc"
carinoPackages="lpf-spotify-client telegram-desktop texlive-scheme-full"
# Flatpak packages
googleFlatpak="com.google.Chrome"
microsoftFlatpak="com.microsoft.Edge com.visualstudio.code com.github.IsmaelMartinez.teams_for_linux"
corporateFlatpak="org.onlyoffice.desktopeditors "
supportFlatpak="com.anydesk.Anydesk com.github.tchx84.Flatseal"
remoteSupportFlatpak="com.anydesk.Anydesk"
# Pending packages for review
# libadwaita-devel libXtst-devel libX11-devel samba samba-client samba-common minigalaxy
detectArgument() {
    case "$1" in
        quick)
            techSetup
            sudo $pkgm $argInstall $preFlags $basicUserPackages $basicSystemPackages $supportPackages $postFlag
            flatpak install $flatpakRepo $googleFlatpak
            ;;
        nvidia)
            graphicDrivers
            ;;
        amd)
            graphicDrivers
            ;;
        intel)
            graphicDrivers
            ;;
        aspeed)
            graphicDrivers
            ;;
        matrox)
            graphicDrivers
            ;;
        svp)
            installSVP
            ;;
        protonge)
            installproton
            ;;
        simple)
            techSetup
            ;;
        server)
            techSetup
            serverSetup
            ;;
        distrobox)
            distroboxContainers
            ;;
        desktop)
            desktopenvironmentMenu
            ;;
        demo)
            distroDemo
            ;;
        anydesk)
            flathubEnable
            sudo $pkgm $argInstall flatpak -y
            sudo flatpak install $remoteSupportFlatpak -y
            ;;
        *)
            identifyDistro
            ;;
    esac
}
detectArgument "$1"
echo $1