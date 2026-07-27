#!/bin/bash
# Setup script
# Log all output to file
if [[ "$1" == "dry-run" || "$1" == "--dry-run" ]]; then DRYRUN=1; shift; else DRYRUN=${CARINO_SETUP_DRYRUN:-0}; fi # a modifier rather than an action, so it prefixes any other argument and leaves the dispatch below unchanged
LOG="${CARINO_SETUP_LOG:-carino-setup-$(date +%Y%m%d-%H%M%S).log}" # one timestamped log per run, replaces the undefined $version and the malformed currentDate
[[ "$DRYRUN" == 1 && -z "$CARINO_SETUP_LOG" ]] && LOG=/dev/null # a rehearsal writes no log at all, not even a temporary one, so nothing on the filesystem changes while the shims below print what would have run
OSRELEASE="${CARINO_SETUP_OSRELEASE:-/etc/os-release}" # overridable so test.sh can drive identifyDistro through every supported family without those distributions being installed
NONINTERACTIVE=0 # the single flag every prompt in this file reads, runPlan sets it to 1 so each read takes its documented default and says so instead of blocking on stdin
exec > >(tee -a "$LOG") 2>&1
set -f # the package lists carry dnf style globs, without noglob the shell expands ffmpeg*, rocm* and lm*sensors against the working directory and hands the package manager a tarball name instead
# Defining Global Variables
RED="\e[31m"; BLUE="\e[94m"; GREEN="\e[32m"; YELLOW="\e[33m"; ENDCOLOR="\e[0m";USERNAME="MiguelCarino"; REPO="Carino-Systems"; locale_language=$(locale | grep "LANG=" | cut -d'=' -f2); flatpakRepo="flathub" # flathub is the default remote for every family, flathubEnable confirms it

# Declaring Global Functions
# Message Functions
info() { echo -e "${BLUE}$1${ENDCOLOR}"; }
error() { echo -e "${RED}$1${ENDCOLOR}"; }
caution() { echo -e "${YELLOW}$1${ENDCOLOR}"; }
success() { echo -e "${GREEN}$1${ENDCOLOR}"; }
profileWarning() { [[ -n "$2" ]] || caution "No native $1 package list exists for '${DISTRIBUTION:-this system}', only the shared base packages and the Flatpaks below will be installed."; } # the specialised lists are populated in the fedora and debian arms only, on rhel, centos, amazon, arch and opensuse the profile would otherwise look identical to Basic without saying so
setupPrivilege ()
{
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        privilegeTool="root"
        sudo() { if [[ "$1" == "-u" ]]; then local privUser="$2"; shift 2; if command -v runuser >/dev/null 2>&1; then runuser -u "$privUser" -- "$@"; else su "$privUser" -c "$*"; fi; else "$@"; fi; } # every privileged line in this file is written "sudo something", as root that is just execution, and only the -u form of installSVP needs translating back to an unprivileged user
        success "Running as root, no privilege escalation is needed."
    elif command -v sudo >/dev/null 2>&1; then
        privilegeTool="sudo" # the literal calls throughout the file are already correct, nothing is overridden
    elif command -v doas >/dev/null 2>&1; then
        privilegeTool="doas"
        sudo() { command doas "$@"; } # doas spells the target user -u exactly as sudo does, so the arguments pass straight through
        caution "sudo is not installed, doas will be used to elevate."
    elif command -v run0 >/dev/null 2>&1; then
        privilegeTool="run0"
        sudo() { local runArgs=(); while [[ "$1" == "-u" ]]; do runArgs+=("--user=$2"); shift 2; done; command run0 "${runArgs[@]}" "$@"; } # run0 spells the target user --user= instead of -u
        caution "sudo is not installed, run0 will be used to elevate."
    else
        privilegeTool=""
        error "This script installs packages as root, but you are not root and this system has none of sudo, doas or run0. Install one of them, or re-run this script as root. Nothing was run."
        return 1
    fi
    return 0
}
systemFacts ()
{
    kernelVersion=$(uname -r 2>/dev/null)
    [[ -n "$kernelVersion" ]] || kernelVersion="unknown"
    if command -v lscpu >/dev/null 2>&1; then
        archType=$(lscpu | grep -e "^Architecture:" | awk '{print $NF}')
    else
        archType=$(uname -m 2>/dev/null) # lscpu is absent on minimal installs, uname -m is the portable fallback
    fi
    [[ -n "$archType" ]] || archType="unknown"
    if command -v glxinfo >/dev/null 2>&1; then
        hardwareAcceleration=$(glxinfo 2>/dev/null | grep -m 1 "direct rendering" | awk -F': ' '{print $2}')
        hardwareRenderer=$(glxinfo 2>/dev/null | grep -m 1 "OpenGL renderer string" | awk -F': ' '{print $2}')
    fi
    [[ -n "$hardwareAcceleration" ]] || hardwareAcceleration="unknown" # glxinfo ships with mesa-demos, not with a minimal install
    [[ -n "$hardwareRenderer" ]] || hardwareRenderer="unknown"
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        latest_commit=$(curl -s "https://api.github.com/repos/$USERNAME/$REPO/commits?per_page=1" | jq -r '.[0].commit.message' 2>/dev/null | head -n 1)
        latest_kernel=$(curl -s https://www.kernel.org/releases.json | jq -r '.releases[1].version' 2>/dev/null)
    fi
    [[ -n "$latest_commit" && "$latest_commit" != "null" ]] || latest_commit="unknown" # jq is installed later by this very script, so it may be missing here
    [[ -n "$latest_kernel" && "$latest_kernel" != "null" ]] || latest_kernel="unknown"
}
buildMenus ()
{
tech_setup_en_US="Version:1.2\nDetected Distribution: $DISTRIBUTION $VERSION\nLatest GitHub Commit: $latest_commit\nLatest Linux Kernel Version: $latest_kernel\nYour Kernel Version: $kernelVersion\nCPU Architecture: $archType\nHardware acceleration enabled: $hardwareAcceleration\nHardware renderer: $hardwareRenderer\n-------------------------------------\nPlease select an option:\n1. Technical Setup\n2. Purpose Setup\n3. Install a Desktop Environment\n4. Install graphic drivers\n5. Update the system\n6. Server setup\n7. Exit"
tech_setup_ja_JP="バージョン:1.2\n検出されたディストリビューション: $DISTRIBUTION $VERSION\n最新のGitHubコミット: $latest_commit\n最新のLinuxカーネルバージョン: $latest_kernel\nお使いのカーネルバージョン: $kernelVersion\nCPUアーキテクチャ: $archType\nハードウェアアクセラレーション有効: $hardwareAcceleration\nハードウェアレンダラー: $hardwareRenderer\n-------------------------------------\nオプションを選択してください:\n1. 技術的なセットアップ\n2. 目的別セットアップ\n3. デスクトップ環境のインストール\n4. グラフィックドライバーのインストール\n5. システムの更新\n6. サーバーのセットアップ\n7. 終了"
tech_setup_ru_RU="Версия:1.2\nОбнаруженный дистрибутив: $DISTRIBUTION $VERSION\nПоследний коммит в GitHub: $latest_commit\nПоследняя версия ядра Linux: $latest_kernel\nВаша версия ядра: $kernelVersion\nАрхитектура ЦП: $archType\nАппаратное ускорение включено: $hardwareAcceleration\nАппаратный рендерер: $hardwareRenderer\n-------------------------------------\nПожалуйста, выберите опцию:\n1. Техническая настройка\n2. Настройка по назначению\n3. Установка рабочего окружения\n4. Установка графических драйверов\n5. Обновление системы\n6. Настройка сервера\n7. Выход"
tech_setup_es_ES="Versión:1.2\nDistribución Detectada: $DISTRIBUTION $VERSION\nÚltimo Commit de GitHub: $latest_commit\nÚltima Versión del Kernel de Linux: $latest_kernel\nVersión de tu Kernel: $kernelVersion\nArquitectura de la CPU: $archType\nAceleración de Hardware habilitada: $hardwareAcceleration\nRenderizador de Hardware: $hardwareRenderer\n-------------------------------------\nPor favor, seleccione una opción:\n1. Configuración Técnica\n2. Configuración por Propósito\n3. Instalar un Entorno de Escritorio\n4. Instalar controladores gráficos\n5. Actualizar el sistema\n6. Configuración de servidor\n7. Salir"
tech_setup_fi_FI="Versio:1.2\nTunnistettu jakelu: $DISTRIBUTION $VERSION\nViimeisin GitHub-commit: $latest_commit\nViimeisin Linux-ytimen versio: $latest_kernel\nKäytössä oleva ytimen versio: $kernelVersion\nSuorittimen arkkitehtuuri: $archType\nLaitteistokiihdytys käytössä: $hardwareAcceleration\nLaitteistorenderöijä: $hardwareRenderer\n-------------------------------------\nValitse vaihtoehto:\n1. Tekninen asennus\n2. Käyttötarkoituksen asennus\n3. Työpöytäympäristön asennus\n4. Näytönohjaimen ajureiden asennus\n5. Järjestelmän päivitys\n6. Palvelinasennus\n7. Poistu"
tech_setup_zh_CN="版本：1.2\n检测到的发行版：$DISTRIBUTION $VERSION\n最新的GitHub提交：$latest_commit\n最新的Linux内核版本：$latest_kernel\n您的内核版本：$kernelVersion\nCPU架构：$archType\n硬件加速已启用：$hardwareAcceleration\n硬件渲染器：$hardwareRenderer\n-------------------------------------\n请选择一个选项：\n1. 技术设置\n2. 用途设置\n3. 安装桌面环境\n4. 安装图形驱动程序\n5. 更新系统\n6. 服务器设置\n7. 退出"
tech_setup_ko_KR="버전:1.2\n감지된 배포판: $DISTRIBUTION $VERSION\n최신 GitHub 커밋: $latest_commit\n최신 Linux 커널 버전: $latest_kernel\n사용 중인 커널 버전: $kernelVersion\nCPU 아키텍처: $archType\n하드웨어 가속 활성화됨: $hardwareAcceleration\n하드웨어 렌더러: $hardwareRenderer\n-------------------------------------\n옵션을 선택하세요:\n1. 기술 설정\n2. 용도별 설정\n3. 데스크톱 환경 설치\n4. 그래픽 드라이버 설치\n5. 시스템 업데이트\n6. 서버 설정\n7. 종료"
tech_setup_he_IL="גרסה:1.2\nהפצה שזוהתה: $DISTRIBUTION $VERSION\nקומיט אחרון ב-GitHub: $latest_commit\nגרסת ליבת Linux האחרונה: $latest_kernel\nגרסת הליבה שלך: $kernelVersion\nארכיטקטורת CPU: $archType\nהאצת חומרה מופעלת: $hardwareAcceleration\nמנוע רינדור חומרה: $hardwareRenderer\n-------------------------------------\nבחר אפשרות:\n1. הגדרה טכנית\n2. הגדרה לפי מטרה\n3. התקנת סביבת שולחן עבודה\n4. התקנת מנהלי התקנים גרפיים\n5. עדכון המערכת\n6. הגדרת שרת\n7. יציאה"
purpose_setup_en_US="-------------------------------------\nPlease select a purpose for your distro\n-------------------------------------\n1. Basic\n2. Gaming\n3. Corporate\n4. Corporate (Microsoft only)\n5. Corporate (Google only)\n6. Development\n7. Astronomy\n8. Computational Neuroscience\n9. Design\n10. Music Production\n11. Cybersecurity\n12. Forensics\n13. Scientific\n14. Robotics\n15. Medical Imaging\n16. Back to main menu"
purpose_setup_ja_JP="-------------------------------------\nディストリビューションの用途を選択してください\n-------------------------------------\n1. ベーシック\n2. ゲーミング\n3. 企業向け\n4. 企業向け (Microsoftのみ)\n5. 企業向け (Googleのみ)\n6. 開発\n7. 天文学\n8. 計算論的神経科学\n9. デザイン\n10. 音楽制作\n11. サイバーセキュリティ\n12. デジタルフォレンジック\n13. 科学技術計算\n14. ロボティクス\n15. 医用画像\n16. メインメニューに戻る"
purpose_setup_ru_RU="-------------------------------------\nВыберите назначение вашего дистрибутива\n-------------------------------------\n1. Базовый\n2. Игровой\n3. Корпоративный\n4. Корпоративный (только Microsoft)\n5. Корпоративный (только Google)\n6. Разработка\n7. Астрономия\n8. Вычислительная нейробиология\n9. Дизайн\n10. Производство музыки\n11. Кибербезопасность\n12. Компьютерная криминалистика\n13. Научный\n14. Робототехника\n15. Медицинская визуализация\n16. Вернуться в главное меню"
purpose_setup_es_ES="-------------------------------------\nSeleccione un propósito para su distro\n-------------------------------------\n1. Básico\n2. Juegos\n3. Corporativo\n4. Corporativo (solo Microsoft)\n5. Corporativo (solo Google)\n6. Desarrollo\n7. Astronomía\n8. Neurociencia Computacional\n9. Diseño\n10. Producción Musical\n11. Ciberseguridad\n12. Informática Forense\n13. Científico\n14. Robótica\n15. Imagenología\n16. Volver al menú principal"
purpose_setup_fi_FI="-------------------------------------\nValitse käyttötarkoitus jakelullesi\n-------------------------------------\n1. Perus\n2. Pelaaminen\n3. Yrityskäyttö\n4. Yrityskäyttö (vain Microsoft)\n5. Yrityskäyttö (vain Google)\n6. Ohjelmistokehitys\n7. Tähtitiede\n8. Laskennallinen neurotiede\n9. Suunnittelu\n10. Musiikkituotanto\n11. Kyberturvallisuus\n12. Digitaalinen forensiikka\n13. Tieteellinen\n14. Robotiikka\n15. Lääketieteellinen kuvantaminen\n16. Takaisin päävalikkoon"
purpose_setup_zh_CN="-------------------------------------\n请选择您的发行版用途\n-------------------------------------\n1. 基础\n2. 游戏\n3. 企业\n4. 企业 (仅 Microsoft)\n5. 企业 (仅 Google)\n6. 开发\n7. 天文学\n8. 计算神经科学\n9. 设计\n10. 音乐制作\n11. 网络安全\n12. 数字取证\n13. 科学计算\n14. 机器人技术\n15. 医学影像\n16. 返回主菜单"
purpose_setup_ko_KR="-------------------------------------\n배포판의 용도를 선택하세요\n-------------------------------------\n1. 기본\n2. 게이밍\n3. 기업용\n4. 기업용 (Microsoft 전용)\n5. 기업용 (Google 전용)\n6. 개발\n7. 천문학\n8. 계산 신경과학\n9. 디자인\n10. 음악 제작\n11. 사이버 보안\n12. 디지털 포렌식\n13. 과학 계산\n14. 로보틱스\n15. 의료 영상\n16. 메인 메뉴로 돌아가기"
purpose_setup_he_IL="-------------------------------------\nבחר מטרה עבור ההפצה שלך\n-------------------------------------\n1. בסיסי\n2. משחקים\n3. ארגוני\n4. ארגוני (Microsoft בלבד)\n5. ארגוני (Google בלבד)\n6. פיתוח\n7. אסטרונומיה\n8. מדעי המוח החישוביים\n9. עיצוב\n10. הפקת מוזיקה\n11. אבטחת סייבר\n12. פורנזיקה דיגיטלית\n13. מדעי\n14. רובוטיקה\n15. הדמיה רפואית\n16. חזרה לתפריט הראשי"
}
# Declaring Specific Functions
identifyDistro ()
{
if [[ -f "$OSRELEASE" ]]; then
        source "$OSRELEASE"
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
    distroType="package" # only the rpm-ostree branch below flips this to atomic, techSetup reads it to decide whether repositories can be enabled at all
    case $NAME in
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*|*Bazzite*|*Bluefin*|*Aurora*|*Silverblue*|*Kinoite*|*Sericea*|*Onyx*|*"Universal Blue"*)
    family="fedora"

    # Check if it is an atomic (rpm-ostree) Fedora system
    if command -v rpm-ostree >/dev/null; then
        distroType="atomic"
        pkgm="rpm-ostree"
        argInstall="install"
        argUpdate="upgrade"
        preFlags=""
        postFlags="--allow-inactive"
        updateFlags="" # --allow-inactive is an rpm-ostree install option only, passing postFlags to the upgrade operation makes rpm-ostree reject the whole command
        # Custom grub update function for atomic systems
        grubPath="/etc/default/grub"
        grubUpdate="sudo ostree admin unlock --hotfix && \
                    sudo grub2-mkconfig -o /boot/grub2/grub.cfg && \
                    sudo ostree admin unlock --commit && \
                    sudo rpm-ostree cleanup -m"
    else
        distroType="package"
        pkgm=dnf
        argInstall=install
        argUpdate=update
        preFlags=""
        postFlags="--allowerasing --skip-broken -y"
        updateFlags="-y"
        grubPath="/etc/default/grub"
        grubUpdate="sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    fi

    pkgext="rpm"
    essentialPackages="$essentialPackages $essentialPackagesRPM" # appended once only, the if/else above used to append the same four lists a second time and rpm-ostree rejects duplicate arguments
    basicSystemPackages="$basicSystemPackages $basicSystemPackagesRPM"
    serverPackages="$serverPackagesRPM" # replaced, netcat-traditional and xserver-xorg-video-dummy are Debian names that resolve to nothing on any RPM family
    amdPackages="$amdPackages $amdPackagesRPM"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesRPM"
    virtconPackages="$virtconPackages $virtconPackagesRPM"
    astronomyPackages="$astronomyPackages $astronomyPackagesRPM" # the purpose profile lists are appended for Fedora only, every name below was checked against the fedora and updates repositories and none of the enterprise rebuilds carries the full set
    compneuroPackages="$compneuroPackages $compneuroPackagesRPM"
    designPackages="$designPackages $designPackagesRPM"
    imagenologyPackages="$imagenologyPackages $imagenologyPackagesRPM"
    musicPackages="$musicPackages $musicPackagesRPM"
    securityPackages="$securityPackages $securityPackagesRPM"
    forensicsPackages="$forensicsPackages $forensicsPackagesRPM"
    scientificPackages="$scientificPackages $scientificPackagesRPM"
    roboticsPackages="$roboticsPackages $roboticsPackagesRPM"
    grubPath="/etc/default/grub" # flatpakRepo stays flathub, the fedora remote carries neither com.google.Chrome nor com.microsoft.Edge
    ;;
    *"Red Hat"*)
    caution "RHEL"
    family=rhel
    pkgm=dnf
    pkgext=rpm
    argInstall=install
    argUpdate=update
    preFlags=""
    postFlags="--skip-broken --setopt=strict=0 -y" # --skip-broken only resolves dependency problems, a package name that is in no enabled repository is still a hard "Unable to find a match" that aborts the entire transaction; strict=0 turns that into a warning, which is what this family needs because the shared lists are Fedora shaped and feh, yt-dlp, scrot, goverlay, xxd and @virtualization exist in none of the enterprise rebuilds
    updateFlags="-y"
    essentialPackages="$essentialPackages $essentialPackagesRPM"
    serverPackages="$serverPackagesRPM" # the shared list holds Debian names that resolve to nothing here
    amdPackages="$amdPackages $rhelPackages $amdPackagesRPM"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesRPM"
    virtconPackages="$virtconPackages $virtconPackagesRPM"
    grubPath="/etc/default/grub"
    grubUpdate="sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    ;;
    *"Amazon Linux"*)
    caution "Amazon Linux is headless only: it carries no EPEL, no CRB and no desktop environment groups, so only the essential and server paths are supported here." # matched before the centos arm on purpose, it is dnf shaped but shares none of the RHEL rebuild repositories
    family=amazon
    pkgm=dnf
    pkgext=rpm
    argInstall=install
    argUpdate=update
    preFlags=""
    postFlags="--skip-broken --setopt=strict=0 -y" # Amazon Linux 2023 carries neither EPEL nor CRB and is missing 36 of the 78 names the shared lists ask for, so without this every install here was all-or-nothing and got nothing
    updateFlags="-y"
    essentialPackages="$essentialPackages $essentialPackagesRPM"
    serverPackages="$serverPackagesRPM" # the shared list holds Debian names that resolve to nothing here
    amdPackages="$amdPackages $amdPackagesRPM"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesRPM"
    virtconPackages="$virtconPackages $virtconPackagesRPM"
    grubPath="/etc/default/grub"
    grubUpdate="sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    ;;
    *CentOS*|*Rocky*|*AlmaLinux*|*"Oracle Linux"*|*EuroLinux*|*"Circle Linux"*|*Springdale*|*Anolis*|*OpenCloudOS*|*TencentOS*|*"Alibaba Cloud Linux"*|*CloudLinux*)
    caution "CentOS"
    family=centos
    pkgm=dnf
    pkgext=rpm
    argInstall=install
    argUpdate=update
    preFlags=""
    postFlags="--skip-broken --setopt=strict=0 -y" # same reason as the RHEL arm above, verified on almalinux:9 and centos:stream10, both of which still run dnf 4
    updateFlags="-y"
    essentialPackages="$essentialPackages $essentialPackagesRPM"
    serverPackages="$serverPackagesRPM" # the shared list holds Debian names that resolve to nothing here
    amdPackages="$amdPackages $amdPackagesRPM"
    nvidiaPackages="$nvidiaPackages $nvidiaPackagesRPM"
    virtconPackages="$virtconPackages $virtconPackagesRPM"
    grubPath="/etc/default/grub"
    grubUpdate="sudo grub2-mkconfig -o /boot/grub2/grub.cfg"

    ;;
    *Debian*|*Ubuntu*|*Pop!_OS*|*"Linux Mint"*|*LMDE*|*Zorin*|*elementary*|*Kali*|*Parrot*|*Devuan*|*Raspbian*|*"Raspberry Pi OS"*|*MX*|*antiX*|*Deepin*|*deepin*|*"KDE neon"*|*Trisquel*|*PureOS*|*TUXEDO*|*PikaOS*|*Armbian*|*SparkyLinux*|*Q4OS*) # the Ubuntu flavours all report NAME=Ubuntu so *Kubuntu*/*Lubuntu*/*Xubuntu* were dead patterns, and Mint reports "Linux Mint" with a space so *Linuxmint* never matched
    family=debian
    pkgm=apt
    pkgext=deb
    argInstall=install
    argUpdate=update
    argUpgrade=upgrade # apt update only refreshes the index, the packages themselves move on the separate upgrade operation that updateSystem and serverSetup run after it
    preFlags="-f"
    postFlags="-y -m"
    updateFlags="-y"
    essentialPackages="$essentialPackages $essentialPackagesDebian"
    basicSystemPackages="$basicSystemPackages $basicSystemPackagesDebian"
    basicDesktopEnvironmentPackages="$basicDesktopEnvironmentPackagesDebian" # replaced, Debian has no package called fontawesome-fonts and apt -m does not forgive an unresolvable name
    amdPackages="$amdPackages $amdPackagesDebian"
    case "${ID:-} ${ID_LIKE:-} ${NAME:-}" in # Ubuntu is checked first on purpose, its ID_LIKE is debian while Mint, Pop!_OS, Zorin and elementary all carry ubuntu in theirs, so a debian first test would hand them Debian only package names
    *ubuntu*|*Ubuntu*) nvidiaFlavour="ubuntu"; nvidiaPackages="$nvidiaPackagesUbuntu" ;;
    *debian*|*Debian*) nvidiaFlavour="debian"; nvidiaPackages="$nvidiaPackagesDebian" ;;
    *) nvidiaFlavour=""; nvidiaPackages="" ;; # nvidiaInstall refuses on an empty list rather than handing apt a name from the wrong archive
    esac # replaced rather than appended, the shared value is Fedora shaped (xorg-x11-drv-nvidia-cuda, libva-utils, vulkan) and apt aborts with exit 100 on every one of those, which graphicDrivers then ignored while telling the user the drivers were installed
    virtconPackages="$virtconPackages $virtconPackagesDebian"
    astronomyPackages="$astronomyPackages $astronomyPackagesDebian" # every name below exists in both Debian trixie main and Ubuntu noble, nothing here needs contrib or non-free
    compneuroPackages="$compneuroPackages $compneuroPackagesDebian"
    designPackages="$designPackages $designPackagesDebian"
    imagenologyPackages="$imagenologyPackages $imagenologyPackagesDebian"
    musicPackages="$musicPackages $musicPackagesDebian"
    securityPackages="$securityPackages $securityPackagesDebian"
    forensicsPackages="$forensicsPackages $forensicsPackagesDebian"
    scientificPackages="$scientificPackages $scientificPackagesDebian"
    roboticsPackages="$roboticsPackages $roboticsPackagesDebian"
    grubPath="/etc/default/grub"
    grubUpdate="sudo update-grub"
    ;;
    *SteamOS*|*Holo*)
    error "SteamOS is not supported: pacman is present but / is a read only A/B image, so anything installed here needs steamos-readonly disable and is destroyed by the next system image update." # excluded from the arch patterns deliberately, it would look like it worked and silently revert
    ;;
    *Artix*)
    error "Artix is not supported: the packages match Arch but the init does not, it runs OpenRC, runit, s6 or dinit depending on the edition, so the systemctl calls this script chains onto every desktop install cannot enable your session."
    ;;
    *Parabola*)
    error "Parabola is not supported: it is a libre only Arch derivative, so the proprietary NVIDIA driver, Steam and the codec packages this script installs are absent by policy rather than renamed."
    ;;
    *Arch*|*Manjaro*|*EndeavourOS*|*Garuda*|*CachyOS*|*ArcoLinux*|*RebornOS*|*Archcraft*)
    caution "Arch"
    family=arch
    pkgm=pacman
    pkgext="pkg.tar.zst"
    argInstall="-S"
    argUpdate="-Syu"
    preFlags=""
    postFlags="--noconfirm --needed" # pacman permutes its options so trailing flags are accepted, and they have to live here because graphicDrivers reaches for postFlags only
    updateFlags="--noconfirm"
    essentialPackages="$essentialPackagesArch" # replaced rather than appended, pacman expands no wildcards in install targets so every globbed name in the shared list is a hard "target not found"
    basicUserPackages="$basicUserPackagesArch"
    basicSystemPackages="$basicSystemPackagesArch"
    basicDesktopEnvironmentPackages="$basicDesktopEnvironmentPackagesArch"
    i3RicingPackages="$i3RicingPackagesArch" # nitrogen is AUR only, and the i3 install is a single pacman transaction that an unknown target aborts
    serverPackages="$serverPackagesArch"
    developmentPackages="$developmentPackagesArch"
    supportPackages="$supportPackagesArch"
    ciscoPackages="$ciscoPackagesArch" # the shared value is a Webex .rpm URL, pacman cannot install an RPM and would abort the whole Corporate transaction over it
    intelPackages="$intelPackagesArch"
    amdPackages="$amdPackagesArch"
    nvidiaPackages="$nvidiaPackagesArch"
    virtconPackages="$virtconPackagesArch"
    grubPath="/etc/default/grub"
    grubUpdate="sudo grub-mkconfig -o /boot/grub/grub.cfg"
    ;;
    *Gentoo*)
    error "Gentoo is not supported: it is source based, so installing a desktop is not one emerge but a profile switch that changes global USE flags and forces a full emerge -uDN @world rebuild, package atoms are category qualified (x11-wm/i3, not i3) so no shared name list survives, and USE flag or licence conflicts are resolved interactively with --autounmask-write plus dispatch-conf, which no flag can automate away."
    ;;
    *Slackware*)
    error "Slackware is not supported: installpkg, upgradepkg and slackpkg resolve no dependencies at all, so a script whose premise is 'name twenty five packages and let the manager sort out the rest' would leave half linked, unusable software behind. Anything outside the official tree comes from SlackBuilds.org source scripts that compile locally."
    ;;
    *NixOS*)
    error "NixOS is not supported: the system is declared in /etc/nixos/configuration.nix and realised with nixos-rebuild switch, there is no imperative system wide install. nix-env writes to a per user profile that the next rebuild ignores, desktops are options rather than packages, and the bootloader is boot.loader.* instead of /etc/default/grub. Supporting it would mean emitting Nix expressions, which is a different tool."
    ;;
    *Guix*)
    error "Guix System is not supported: like NixOS it is declarative (an operating-system declaration plus guix system reconfigure) and guix install only touches a profile. It is also FSF endorsed, so the NVIDIA driver, Steam and the freeworld codecs are absent by policy, not renamed."
    ;;
    *Alpine*)
    error "Alpine is not supported: musl libc rules out the proprietary NVIDIA driver and every glibc-only tarball this script downloads, OpenRC means the systemctl calls are hard errors, and the base image has neither GRUB nor sudo."
    ;;
    *Void*)
    error "Void is not supported: xbps would fit, but runit means a desktop install needs ln -s /etc/sv/gdm /var/service instead of systemctl, and the same NAME covers both the glibc and the musl package sets, so /etc/os-release cannot tell which one is valid."
    ;;
    *"Clear Linux"*)
    error "Clear Linux is not supported: swupd manages curated bundles rather than packages, so there is no per package mapping to write, and Intel has discontinued the distribution."
    ;;
    *Solus*)
    error "Solus is not supported yet: it is mid migration off the classic eopkg format and the desktop component names the menu would depend on are exactly what is in flux. It also boots with clr-boot-manager and systemd-boot, so the GRUB paths do not apply."
    ;;
    *Qubes*)
    error "Qubes is not supported: dom0 has no network by design, updates arrive through qubes-dom0-update, and installing user applications into dom0 is contrary to the security model. Run this script inside a Fedora or Debian template instead, both are already supported."
    ;;
    *Mageia*|*OpenMandriva*)
    error "Mageia and OpenMandriva are not supported yet: library packages carry lib64 prefixes that match nothing in the shared lists and the task-* desktop metapackages are renamed between releases, so any mapping written from memory would fail on your machine rather than here."
    ;;
    *Chimera*)
    error "Chimera is not supported: it combines apk with musl, dinit and a FreeBSD derived userland, so the libc, the init calls and the coreutils all differ at once."
    ;;
    *MicroOS*|*Aeon*|*Kalpa*|*"Leap Micro"*|*"SLE Micro"*|*"SL Micro"*)
    error "Transactional openSUSE is not supported: transactional-update takes its options before the subcommand and each call branches a fresh snapshot off the running system, so the several sequential installs this script performs would keep only the last one and none of them would be visible until reboot." # matched before the openSUSE arm, NAME is literally "openSUSE MicroOS" so the zypper arm would otherwise swallow it and write to a read only /usr
    ;;
    *openSUSE*|*SUSE*|*SLES*|*SLED*)
    caution "openSUSE is being tested."
    family=opensuse
    pkgm=zypper
    pkgext=rpm
    argInstall=install
    argUpdate=refresh
    case $NAME in *Tumbleweed*|*Slowroll*) argUpgrade="dup" ;; *) argUpgrade="update" ;; esac # zypper refresh only rewrites the repository metadata, so updateSystem and serverSetup reported success having upgraded nothing at all; the rolling releases have to be upgraded with dup, on Tumbleweed zypper update deliberately holds back every package whose dependencies changed, which is most of a snapshot
    preFlags="-n"
    postFlags=""
    updatePreFlags="-n" # only zypper needs a pre-command flag on the refresh operation, this is deliberately separate from preFlags because apt rejects the debian family's -f there with exit 100 and refreshes nothing
    updateFlags="" # zypper refresh takes neither -y nor --skip-broken, preFlags -n already answers its prompts
    essentialPackages="$essentialPackagesOpenSUSE" # replaced rather than appended: zypper has no --skip-broken and no strict=0, one unresolvable name aborts the whole transaction with exit 104 and installs nothing, and the shared list carries lm*sensors which matches no openSUSE package
    basicUserPackages="$basicUserPackagesOpenSUSE" # ffmpeg* is the only difference, as a glob it pulls in ffmpeg-7-mini-devel whose dependencies cannot be satisfied and the whole purpose profile dies on it
    basicSystemPackages="$basicSystemPackagesOpenSUSE" # replaced, the shared list carries libxdo-* which resolves to nothing here, so every purpose profile aborted before installing anything
    supportPackages="$supportPackagesOpenSUSE" # xxd is its own package on Tumbleweed but not on Leap 15.6, where it ships inside vim
    gamingPackages="$gamingPackagesOpenSUSE"
    developmentPackages="$developmentPackagesOpenSUSE" # conda is packaged for no openSUSE release and ncurses-dev* matches nothing on Leap
    serverPackages="$serverPackagesOpenSUSE" # replaced, netcat-traditional and xserver-xorg-video-dummy are Debian names and zypper aborts on an unknown one
    amdPackages="$amdPackagesOpenSUSE" # replaced, the shared list carries rocm*, which resolves on Tumbleweed but matches nothing on Leap 16.0 and takes the whole transaction down with exit 104
    nvidiaPackages="$nvidiaPackagesOpenSUSE" # replaced, appending an empty openSUSE list left zypper with the Fedora names and exit 104, verified on opensuse/tumbleweed
    nvidiaInstallFlags="--auto-agree-with-licenses" # the G06 packages carry NVIDIA's licence and zypper stops with exit 4 asking for confirmation, which under -n it can never get; it sits after the install subcommand, so it cannot live in preFlags
    virtconPackages="$virtconPackages $virtconPackagesOpenSUSE"
    grubPath="/etc/default/grub"
    grubUpdate="sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
    ;;
    *)
    error "Unsupported distribution: '${DISTRIBUTION:-unknown}' ${VERSION:-}. No package manager, package family or flags were configured, so every install below would be a no-op." # names what was actually read from /etc/os-release instead of printing the bare string "2"
    ;;
    esac # identifyDistro detects only, detectArgument decides what runs next
}
load_dictionary() {
    [[ "$NONINTERACTIVE" == 1 ]] && return 0 # a menu is a request for input, and under a plan the input is already known, so nothing is drawn
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
  phase=tech_setup
  while true; do
    load_dictionary
    if ! read -r -p "Enter a number [1-7]: " optionmenu; then
        caution "There is no more input to read, so the menu is closing. Nothing further was run." # the menu is redrawn after every action now, so a piped stdin runs out and has to be handled rather than looping forever
        return 0
    fi
    case $optionmenu in
      1)
          caution "Tech Setup is starting..."
          techSetup
          askReboot
          ;; # the tail call to displayMenu that used to sit here is what the loop replaces, so a long session no longer nests one shell frame per menu visit
      2)
          purposeMenu
          ;;
      3)
          desktopenvironmentMenu && finalTweaks # the tweaks only run when a desktop was actually installed
          ;;
      4)
          graphicDrivers
          ;;
      5)
          caution "Updating the system"
          updateSystem
          ;;
      6)
          caution "Server Setup Runs"
          serverSetup
          ;;
      7)
          caution "Exit"
          return 0
          ;;
      *)
          error "Bad input: '$optionmenu' is not one of 1-7. Please choose again."
          ;;
    esac
  done
}
desktopenvironment ()
{
    if [[ -n $XDG_CURRENT_DESKTOP ]]; then
        success "You have $XDG_CURRENT_DESKTOP installed already, moving on"
    elif [[ "$NONINTERACTIVE" == 1 ]]; then
        caution "Non-interactive run: no desktop environment was chosen (default: none). Add desktop=<name> to CARINO_SETUP_PLAN to install one."
        return 1 # the same status a declined menu returns, so the caller skips the tweaks for a desktop that was never installed
    else
        desktopenvironmentMenu || return 1 # XDG_CURRENT_DESKTOP is set by the session, never by a just-run install, so the old message here was always blank and was printed even when the user declined or the install failed
    fi
}
enableDisplayManager ()
{
    command -v systemctl >/dev/null 2>&1 || return 0 # sysvinit, runit and OpenRC derivatives have no systemctl, the display manager has to be enabled by hand there
    for displayManager in gdm sddm lightdm; do
        case " $1 " in *" $displayManager "*) sudo systemctl enable "$displayManager" && success "$displayManager was enabled" ;; esac # no Arch desktop metapackage enables a greeter, without this the box boots straight into a black graphical.target
    done
}
installDesktopEnvironment ()
{
    dePackagesVar="${family}${1}Packages"
    dePackages=${!dePackagesVar}
    if [[ -z "$family" || -z "$dePackages" ]]; then
        error "No $1 package list exists for '${DISTRIBUTION:-this system}' (looked up \$$dePackagesVar), refusing to install." # an unmapped family used to expand to nothing, install nothing and still report success
        return 1
    fi
    shift
    info "$dePackages $*"
    sudo $pkgm $preFlags $argInstall $dePackages "$@" $postFlags || return 1
    enableDisplayManager "$dePackages"
    if command -v systemctl >/dev/null 2>&1; then sudo systemctl set-default graphical.target; else caution "No systemctl on this system, set the default runlevel and enable your display manager by hand."; fi
}
desktopenvironmentMenu ()
{
  if [[ "$NONINTERACTIVE" == 1 ]]; then
      caution "Non-interactive run: no desktop menu is drawn and the default is taken, which is none. Add desktop=<name> to CARINO_SETUP_PLAN to install one."
      return 1
  fi
  while true; do
    caution "What Desktop Environment you want?\n1. GNOME\n2. XFCE\n3. KDE\n4. LXQT\n5. CINNAMON\n6. MATE\n7. i3\n8. OPENBOX\n9. BUDGIE\n10. SWAY\n11. HYPRLAND\n12. NIRI\n13. NONE" # 12 is niri and 13 is none, the printed list now matches the case bodies
    if ! read -r -p "Enter a number [1-13]: " option; then
        caution "There is no more input to read, so no desktop environment was chosen and none was installed. Run this step again from a terminal, or use desktop=<name> in CARINO_SETUP_PLAN." # a piped or closed stdin used to fall into the wildcard below and kill the whole run
        return 1
    fi
    case $option in
      1)
          installDesktopEnvironment gnome && success "You have GNOME installed, moving on"
          ;;
      2)
          installDesktopEnvironment xfce $basicDesktopEnvironmentPackages && success "You have XFCE installed, moving on"
          ;;
      3)
          installDesktopEnvironment kde && success "You have KDE installed, moving on"
          ;;
      4)
          installDesktopEnvironment lxqt && success "You have LXQT installed, moving on"
          ;;
      5)
          installDesktopEnvironment cinnamon && success "You have CINNAMON installed, moving on"
          ;;
      6)
          installDesktopEnvironment mate && success "You have MATE installed, moving on"
          ;;
      7)
          installDesktopEnvironment i3 $i3RicingPackages $basicDesktopEnvironmentPackages && success "You have i3 installed, moving on"
          ;;
      8)
          installDesktopEnvironment openbox && success "You have OPENBOX installed, moving on"
          ;;
      9)
          installDesktopEnvironment budgie && success "You have BUDGIE installed, moving on"
          ;;
      10)
          installDesktopEnvironment sway $basicDesktopEnvironmentPackages && success "You have SWAY installed, moving on"
          ;;
      11)
          info "Still on the works"
          installDesktopEnvironment hyprland $basicDesktopEnvironmentPackages && success "You have HYPRLAND installed, moving on"
          ;;
      12)
          info "Still on the works"
          niriRepo # niri lives in a copr on Fedora, the repo has to be enabled before installing
          installDesktopEnvironment niri $basicDesktopEnvironmentPackages && success "You have NIRI installed, moving on"
          ;;
      13)
          caution "No Desktop Environment will be installed"
          return 1 # a non-zero status so the caller skips finalTweaks, which would otherwise rewrite the dotfiles of a desktop the user just declined
          ;;
      *)
          error "Bad input: '$option' is not one of 1-13. Please choose again."
          continue # this arm used to be a bare exit, the only one in the file, and techSetup reaches this menu automatically on any machine with an empty XDG_CURRENT_DESKTOP, so one mistyped character killed the run and skipped the drivers, the tweaks and the reboot offer
          ;;
    esac
    return $? # the status of whichever arm ran, so a refused or failed install still tells the caller to skip finalTweaks
  done
}
nvidiaRepoSetup ()
{
    case "$family" in
    debian)
        [[ "$nvidiaFlavour" == "ubuntu" ]] && return 0 # the driver metapackages are in the restricted component, which every stock Ubuntu install already enables, so there is nothing to add here
        if [[ "${ID:-}" != "debian" ]]; then
            caution "'${DISTRIBUTION:-this system}' is Debian based but is not Debian itself, so its own archive is left exactly as it is. If the install below fails, enable the contrib, non-free and non-free-firmware components the way your distribution documents and run this step again." # writing a deb.debian.org stanza onto Kali, Devuan or PureOS would mix two archives, which is worse than an honest failure
            return 0
        fi
        if [[ -z "${VERSION_CODENAME:-}" ]]; then
            error "Debian keeps the NVIDIA driver in contrib, non-free and non-free-firmware, and this system's os-release carries no VERSION_CODENAME, so the components cannot be enabled for the right suite. Enable them by hand as described at https://wiki.debian.org/NvidiaGraphicsDrivers and run this step again. Nothing was installed."
            return 1
        fi
        info "Enabling the contrib, non-free and non-free-firmware components, the NVIDIA driver needs all three and Debian enables none of them by default." # a new deb822 drop-in rather than a sed over the dpkg managed debian.sources, and it reuses the stock keyring that already ships in the base system, so no key work is involved; add-apt-repository is not an option, software-properties-common exists in no component of trixie
        sudo tee /etc/apt/sources.list.d/carino-nonfree.sources >/dev/null <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $VERSION_CODENAME $VERSION_CODENAME-updates
Components: contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: $VERSION_CODENAME-security
Components: contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
EOF
        sudo $pkgm $argUpdate || { error "The package index could not be refreshed after enabling the non-free components, so the driver names below would still be invisible. Nothing was installed."; return 1; }
        ;;
    opensuse)
        case $NAME in
        *Tumbleweed*) suseNvidiaRepo="openSUSE-repos-Tumbleweed-NVIDIA" ;;
        *Slowroll*) suseNvidiaRepo="openSUSE-repos-Slowroll-NVIDIA" ;;
        *Leap*) suseNvidiaRepo="openSUSE-repos-Leap-NVIDIA" ;;
        *) error "The NVIDIA driver for '${DISTRIBUTION:-this system}' comes from SUSE's own channels rather than from an openSUSE-repos-* package, and guessing a repository URL here would be worse than saying so. See https://en.opensuse.org/SDB:NVIDIA_drivers and install it by hand. Nothing was installed."; return 1 ;;
        esac
        info "Adding NVIDIA's own repository through $suseNvidiaRepo, the OSS repository carries the signed kernel module but none of the userspace libraries."
        sudo $pkgm $preFlags $argInstall $suseNvidiaRepo $postFlags || { error "$suseNvidiaRepo could not be installed, so NVIDIA's repository was never added and the driver packages do not exist yet. Nothing was installed."; return 1; }
        sudo $pkgm $preFlags --gpg-auto-import-keys refresh || { error "NVIDIA's repository was added but could not be refreshed, so its packages are still invisible. Nothing was installed."; return 1; } # the repository is signed with NVIDIA's own key, which zypper would otherwise stop and ask about
        ;;
    rhel|centos)
        error "akmod-nvidia and xorg-x11-drv-nvidia-cuda are Fedora spellings. RPM Fusion's enterprise branch publishes only version numbered variants of them, so no repository this script can enable provides the names in the list above, and pinning '${DISTRIBUTION:-this system}' to one driver series here would rot with the next release. Install the driver as https://elrepo.org/wiki/doku.php?id=nvidia-kmod describes and run the rest of this script afterwards. Nothing was installed." # verified on almalinux:9 with EPEL, CRB and both RPM Fusion el9 release packages enabled: akmod-nvidia and xorg-x11-drv-nvidia-cuda still resolve to nothing while akmod-nvidia-580xx, -470xx, -390xx and -340xx all exist, so enabling RPM Fusion here would leave the transaction reporting success having installed no driver at all
        return 1
        ;;
    fedora)
        if [[ "$distroType" == "atomic" ]]; then
            error "akmod-nvidia is built against the running kernel, which rpm-ostree cannot do while layering, so the driver cannot be installed from here on an atomic system. Rebase to the image variant that already ships it, or follow https://rpmfusion.org/Howto/NVIDIA. Nothing was installed." # the Universal Blue images publish an -nvidia variant for exactly this, layering the akmod on top of the stock image leaves a machine that boots into nouveau
            return 1
        fi
        if [[ -f /etc/yum.repos.d/rpmfusion-free.repo && -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]]; then
            caution "RPM Fusion is enabled already, moving on"
            return 0
        fi
        rpmfusionRelease=$(rpm -E %fedora 2>/dev/null) # RPM Fusion publishes one release package per Fedora major and the macro is the only thing that knows which one this is
        [[ "$rpmfusionRelease" =~ ^[0-9]+$ ]] || rpmfusionRelease="${VERSION%%.*}" # Nobara, Ultramarine and Risi all keep the macro, this is the same os-release fallback techSetup uses for the RHEL EPEL release
        if ! [[ "$rpmfusionRelease" =~ ^[0-9]+$ ]]; then
            error "akmod-nvidia, xorg-x11-drv-nvidia-cuda and libva-nvidia-driver all live in RPM Fusion, and the Fedora release of '${DISTRIBUTION:-this system}' could not be determined, so the right release package cannot be named. Enable RPM Fusion as described at https://rpmfusion.org/Configuration and run this step again. Nothing was installed."
            return 1
        fi
        info "Enabling RPM Fusion free and nonfree, the NVIDIA driver packages are in no repository a stock '${DISTRIBUTION:-this system}' has enabled." # verified on fedora:43, the driver list resolves to 519 packages once these two are installed and aborts the whole transaction with three "No match for argument" lines without them, which is what this step did on every Fedora that had not run Technical Setup first
        sudo $pkgm $preFlags $argInstall https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$rpmfusionRelease.noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$rpmfusionRelease.noarch.rpm $postFlags || { error "RPM Fusion could not be enabled, so the NVIDIA driver packages do not exist on this system yet. Follow https://rpmfusion.org/Configuration and run this step again. Nothing was installed."; return 1; }
        ;;
    esac
    return 0
}
nvidiaInstall ()
{
    if [[ -z "$nvidiaPackages" ]]; then
        error "No NVIDIA package list exists for '${DISTRIBUTION:-this system}', so nothing was installed. Follow your distribution's own NVIDIA documentation rather than letting this script guess a package name." # a guessed name aborts the whole transaction and installs nothing anyway, so refusing here is the same outcome said out loud
        return 1
    fi
    nvidiaRepoSetup || return 1
    sudo $pkgm $preFlags $argInstall $nvidiaInstallFlags $nvidiaPackages $postFlags || return 1 # the exit status used to be thrown away, so an aborted transaction still printed a success message and the user rebooted into nouveau
    if [[ "$nvidiaFlavour" == "ubuntu" ]]; then
        sudo ubuntu-drivers install || return 1 # ubuntu-drivers-common was installed by the line above, and this is the step that actually picks and installs the metapackage matching the card
    fi
    return 0
}
graphicDrivers ()
{
    info "Installing GPU drivers"
    if [[ -z "$pkgm" ]]; then
        error "No package manager was configured for '${DISTRIBUTION:-unknown}', no driver can be installed here." # without this the install lines collapse to "sudo vdpauinfo libva-utils ...", which runs the first package name as root
        return 1
    fi
    if ! command -v lspci >/dev/null 2>&1; then
        caution "lspci is missing, the GPU cannot be identified. Skipping the driver step." # pciutils only arrives with essentialPackages, so a fresh minimal install reaches here without it
        return 0
    fi
    [[ -n "$archType" ]] || systemFacts
    if [[ "$archType" != "x86_64" && "$archType" != "amd64" ]]; then
        caution "The proprietary and ROCm driver lists only exist for x86_64, and this machine reports $archType. Skipping the driver step." # Fedora Asahi and the Raspberry Pi images match their families but share none of these packages
        return 0
    fi
    if lspci | grep 'NVIDIA' > /dev/null; then
        if nvidia-smi > /dev/null 2>&1; then
            success "NVIDIA drivers are installed already."
        else
            caution "NVIDIA card detected. Would you like to install NVIDIA packages? (y/n)"
            if [[ "$NONINTERACTIVE" == 1 ]]; then option="y"; caution "Non-interactive run: answering yes (default), the drivers were asked for explicitly."; else read -r option; fi
            if [[ "$option" =~ ^[Yy]$ ]]; then
                info "Installing the NVIDIA driver" # the message used to promise CUDA as well, and $cudaPackages is set nowhere in this file, so it always expanded to nothing; the runtime half of CUDA arrives with the driver on every family here and the developer toolkit is a 200 MB opt-in that does not belong in a driver step
                if nvidiaInstall; then
                    success "The NVIDIA driver was installed. Reboot before expecting it to be in use, the running kernel is still on the open source module."
                else
                    error "The NVIDIA driver install FAILED. Nothing usable was installed and this machine is still on nouveau, so do not treat the rest of this run as a working driver. The package manager's own message above says which step failed."
                fi
            else
                caution "NVIDIA packages will not be installed."
            fi
        fi
    elif lspci | grep -E 'Radeon|AMD' > /dev/null; then
        if lsmod | grep amdgpu > /dev/null 2>&1; then
            success "AMD drivers are installed already."
        else
            caution "AMD GPU detected. Would you like to install ROCm/HIP packages? (y/n)"
            if [[ "$NONINTERACTIVE" == 1 ]]; then option="y"; caution "Non-interactive run: answering yes (default), the drivers were asked for explicitly."; else read -r option; fi
            if [[ -z "$amdPackages" ]]; then
                error "No AMD package list exists for '${DISTRIBUTION:-this system}', so nothing was installed."
            elif [[ "$option" =~ ^[Yy]$ ]]; then
                info "Installing AMD drivers and ROCm/HIP support"
                sudo $pkgm $preFlags $argInstall $amdPackages $postFlags && success "The AMD packages were installed." || error "The AMD driver install FAILED, nothing was installed. Read the package manager's message above." # the status used to be discarded here too
            else
                caution "The same list is installed either way, this script has no separate ROCm free AMD list to fall back to." # said plainly rather than the old claim that ROCm was being left out while the identical command ran
                sudo $pkgm $preFlags $argInstall $amdPackages $postFlags && success "The AMD packages were installed." || error "The AMD driver install FAILED, nothing was installed. Read the package manager's message above."
            fi
        fi
    elif lspci | grep -E 'Intel' > /dev/null; then
        caution "Intel GPU detected. Would you like to install oneAPI packages? (y/n)"
        if [[ "$NONINTERACTIVE" == 1 ]]; then option="y"; caution "Non-interactive run: answering yes (default), the drivers were asked for explicitly."; else read -r option; fi
        if [[ -z "$intelPackages" ]]; then
            error "No Intel package list exists for '${DISTRIBUTION:-this system}', so nothing was installed."
        else
            [[ "$option" =~ ^[Yy]$ ]] && info "Installing the Intel media driver" || caution "The same list is installed either way, this script ships no separate oneAPI list." # the two arms always ran the identical command, only the message differed
            sudo $pkgm $preFlags $argInstall $intelPackages $postFlags && success "The Intel packages were installed." || error "The Intel driver install FAILED, nothing was installed. Read the package manager's message above."
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
    if ! command -v flatpak >/dev/null 2>&1; then
        caution "Flatpak is not installed yet, no remote was added." # the remote is added with the flatpak binary itself, so this has to be checked before calling it
        return 0
    fi
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo # one command for every family, the CentOS arm only differed by using flathub.org, which is a redirect to this same dl.flathub.org URL
    flatpakRepo="flathub"
    flathubReady=1
}
flatpakInstall ()
{
    [[ $# -gt 0 ]] || return 0 # a profile with no Flatpaks of its own passes nothing, and "flatpak install flathub -y" with no application is an error rather than a no-op
    if ! command -v flatpak >/dev/null 2>&1; then
        caution "Flatpak is not installed, installing it before the Flatpak applications below." # basicUserPackages carries flatpak and every profile installs it on the line above this call, this covers the atomic family and a native transaction that failed
        sudo $pkgm $preFlags $argInstall flatpak $postFlags
    fi
    if ! command -v flatpak >/dev/null 2>&1; then
        error "Flatpak could not be installed on '${DISTRIBUTION:-this system}', so none of these applications were installed: $*" # saying so beats fourteen silent "error: no remote refs found" failures
        return 1
    fi
    [[ "${flathubReady:-0}" == 1 ]] || flathubEnable # the single place the remote is guaranteed, called after the native package line has provided the binary rather than from fourteen profile arms; purposeMenu never called flathubEnable at all and techSetup's own call always hit its "command -v flatpak" guard because flatpak is not in essentialPackages
    sudo flatpak install $flatpakRepo "$@" -y
}
updateGrub ()
{
    info "Updating GRUB"
    if [[ ! -f "$grubPath" || -z "$grubUpdate" ]]; then
        caution "No GRUB configuration at '${grubPath:-unset}', skipping the GRUB update." # arm boards boot u-boot and several desktops boot systemd-boot, the sed below would fail on every one of them
        return 0
    fi
    caution "This rewrites GRUB_TIMEOUT in $grubPath and regenerates the bootloader configuration. Continue? [y/N]" # nothing between the menu selection and the sed used to ask, so a user who only wanted the technical setup had their boot configuration changed
    if [[ "$NONINTERACTIVE" == 1 ]]; then option="n"; caution "Non-interactive run: taking the default [N], the bootloader configuration is left alone."; else read -r option; fi
    if [[ ! "$option" =~ ^[Yy]$ ]]; then
        caution "GRUB was left untouched."
        return 0
    fi
    if grep -q '^GRUB_TIMEOUT=' "$grubPath"; then
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' "$grubPath" # anchored and value agnostic, so re-running never stacks entries
    else
        echo "GRUB_TIMEOUT=5" | sudo tee -a "$grubPath" > /dev/null # a zero timeout would remove the only route into recovery after a driver swap
    fi
    eval "$grubUpdate" # grubUpdate already carries its own sudo, and the atomic variant is a && chain
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
        set +f; sudo -u $USER ./$svpName-64.run && rm svp4-latest* $svpName-64.run; set -f # the only place a real glob is wanted, so noglob is lifted for this line alone
    fi
}
sharedFolder ()
{
  #Mounting Windows Shared folder
        echo "Do you want to setup a Windows Shared Folder? [y/N]"
        if [[ "$NONINTERACTIVE" == 1 ]]; then option="n"; caution "Non-interactive run: taking the default [N], no share is mounted because a plan carries no server, folder or user to ask for."; else read -r option; fi
        if [[ "$option" =~ ^[Yy]$ ]]
        then
            echo "What is the server name you wish to connect to?"
            read -r server
            echo "What is the shared folder of $server?"
            read -r folder
            echo "What is the user to connect to $folder in $server?"
            read -r srvuser # the read and the mount had collapsed into a single corrupt statement
            mkdir -p "/home/$(whoami)/WinFiles"
            sudo mount.cifs "//$server/$folder" "/home/$(whoami)/WinFiles/" -o user="$srvuser" && echo "Windows Shared Folder has been successfully mounted!"
        else
            info "No Windows shared folders were added\n--------------------------------------"
        fi
}
installproton() {
  COMPATIBILITY_DIR="$HOME/.steam/root/compatibilitytools.d"
  mkdir -p "$COMPATIBILITY_DIR" # created up front, so nothing below reads an unset variable
  protonRelease=""
  if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    protonRelease=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | jq -r '.tag_name' 2>/dev/null) # asks upstream instead of hardcoding a GE-Proton9 range
  fi
  if [[ -z "$protonRelease" || "$protonRelease" == "null" ]]; then
    error "Could not determine the latest ProtonGE release, skipping."
    return 1
  fi
  if [ -d "$COMPATIBILITY_DIR/$protonRelease" ]; then
    success "You already have the latest ProtonGE $protonRelease version."
    return 0
  fi
  info "Installing $protonRelease..."
  if wget -q "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$protonRelease/$protonRelease.tar.gz"; then
    tar -xf "$protonRelease.tar.gz" -C "$COMPATIBILITY_DIR" && rm -f "$protonRelease.tar.gz"
    success "ProtonGE $protonRelease has been installed."
  else
    caution "ProtonGE $protonRelease could not be downloaded."
  fi
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
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*|*Bazzite*|*Bluefin*|*Aurora*|*Silverblue*|*Kinoite*|*Sericea*|*Onyx*|*"Universal Blue"*)
        if [[ "$distroType" == "atomic" ]]; then
            caution "Copr repositories have to be layered by hand on an atomic system, skipping the niri repository." # rpm-ostree has no copr subcommand, the repo file goes under /etc/yum.repos.d first
        else
            sudo $pkgm copr enable yalter/niri -y
        fi
    ;;
    *Arch*|*Manjaro*|*EndeavourOS*|*Garuda*|*CachyOS*|*ArcoLinux*|*RebornOS*|*Archcraft*)
        info "niri is in the official repositories, no extra repository is needed."
    ;;
    *Debian*|*Ubuntu*|*Pop!_OS*|*"Linux Mint"*|*LMDE*|*Zorin*|*elementary*|*Kali*|*Parrot*|*Devuan*|*Raspbian*|*"Raspberry Pi OS"*|*MX*|*antiX*|*Deepin*|*deepin*|*"KDE neon"*|*Trisquel*|*PureOS*|*TUXEDO*|*PikaOS*|*Armbian*|*SparkyLinux*|*Q4OS*)
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
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*|*Bazzite*|*Bluefin*|*Aurora*|*Silverblue*|*Kinoite*|*Sericea*|*Onyx*|*"Universal Blue"*)
        sudo tee /etc/yum.repos.d/AnyDesk-Fedora.repo > /dev/null << "EOF" # tee writes under sudo, a plain redirect would run as the caller and be denied
[anydesk]
name=AnyDesk Fedora - stable
baseurl=http://rpm.anydesk.com/fedora/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF
    ;;
    *"Red Hat"*)
    sudo tee /etc/yum.repos.d/AnyDesk-RHEL.repo > /dev/null << "EOF" # tee writes under sudo, a plain redirect would run as the caller and be denied
[anydesk]
name=AnyDesk RHEL - stable
baseurl=http://rpm.anydesk.com/rhel/$releasever/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF
    ;;
    *CentOS*|*Rocky*|*AlmaLinux*|*"Oracle Linux"*|*EuroLinux*|*"Circle Linux"*|*Springdale*|*Anolis*|*OpenCloudOS*|*TencentOS*|*"Alibaba Cloud Linux"*|*CloudLinux*)
    sudo tee /etc/yum.repos.d/AnyDesk-CentOS.repo > /dev/null << "EOF" # tee writes under sudo, a plain redirect would run as the caller and be denied
[anydesk]
name=AnyDesk CentOS - stable
baseurl=http://rpm.anydesk.com/centos/$releasever/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF
    ;;

    *openSUSE*|*SUSE*|*SLES*|*SLED*)
    tee AnyDesk-OpenSUSE.repo > /dev/null << "EOF" # written through tee rather than a shell redirect, a redirect is the one file creation in this file that the dry-run shims cannot intercept
[anydesk]
name=AnyDesk OpenSUSE - stable
baseurl=http://rpm.anydesk.com/opensuse/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
EOF

sudo $pkgm addrepo --repo AnyDesk-OpenSUSE.repo
    ;;
    *Debian*|*Ubuntu*|*Pop!_OS*|*"Linux Mint"*|*LMDE*|*Zorin*|*elementary*|*Kali*|*Parrot*|*Devuan*|*Raspbian*|*"Raspberry Pi OS"*|*MX*|*antiX*|*Deepin*|*deepin*|*"KDE neon"*|*Trisquel*|*PureOS*|*TUXEDO*|*PikaOS*|*Armbian*|*SparkyLinux*|*Q4OS*)
        sudo mkdir -p /etc/apt/keyrings
        wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | gpg --dearmor | sudo tee /etc/apt/keyrings/anydesk.gpg > /dev/null # apt-key is removed in Debian 12 and later, a keyring file replaces it
        echo "deb [signed-by=/etc/apt/keyrings/anydesk.gpg] http://deb.anydesk.com/ all main" | sudo tee /etc/apt/sources.list.d/anydesk-stable.list > /dev/null
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
    *Fedora*|*Nobara*|*Risi*|*Ultramarine*|*Bazzite*|*Bluefin*|*Aurora*|*Silverblue*|*Kinoite*|*Sericea*|*Onyx*|*"Universal Blue"*)
        sudo $pkgm config-manager --add-repo https://repo.librewolf.net/librewolf.repo $postFlags
        sudo $pkgm $argInstall librewolf $postFlags
    ;;
    *Debian*|*Ubuntu*|*Pop!_OS*|*"Linux Mint"*|*LMDE*|*Zorin*|*elementary*|*Kali*|*Parrot*|*Devuan*|*Raspbian*|*"Raspberry Pi OS"*|*MX*|*antiX*|*Deepin*|*deepin*|*"KDE neon"*|*Trisquel*|*PureOS*|*TUXEDO*|*PikaOS*|*Armbian*|*SparkyLinux*|*Q4OS*)
        sudo $pkgm $argUpdate && sudo $pkgm $argInstall extrepo $postFlags # argUpdate is already "update" for this family, the stray literal made it "apt update update", which errors out and short circuits the whole chain
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
  if [[ "$NONINTERACTIVE" == 1 ]]; then
      if [[ "${planReboot:-no}" == "yes" ]]; then option="y"; else option="n"; fi # reboot=yes|no in the plan answers this prompt, and the contract makes no the default
      caution "Non-interactive run: reboot=${planReboot:-no} (default: no)."
  else
      read -r option
  fi
    if [[ "$option" =~ ^[Yy]$ ]]
    then
        sudo reboot
    else
        caution "No reboot was requested."
    fi
}
distroboxContainers ()
{
    distrobox-create --name fedora --image quay.io/fedora/fedora:latest -Y
    distrobox-create --name ubuntu --image docker.io/library/ubuntu:latest -Y
    #distrobox-create --name rhel --image registry.access.redhat.com/ubi10/ubi -Y
    distrobox-create --name debian --image docker.io/library/debian:latest -Y
    #distrobox-create --name clearlinux --image docker.io/library/clearlinux:latest -Y
    #distrobox-create --name centos --image quay.io/centos/centos:stream9 -Y
    #distrobox-create --name centos --image quay.io/centos/centos:stream10 -Y
    #distrobox-create --name arch --image docker.io/library/archlinux:latest -Y
    #distrobox-create --name opensusel --image registry.opensuse.org/opensuse/leap:latest -Y
    #distrobox-create --name opensuset --image registry.opensuse.org/opensuse/tumbleweed:latest  -Y
    #distrobox-create --name gentoo --image docker.io/gentoo/stage3:latest -Y
}
purposeMenu ()
{
  if [[ -z "$pkgm" ]]; then
      error "No package manager was configured for '${DISTRIBUTION:-unknown}', no purpose profile can be installed here." # every profile below expands to "sudo gedit yt-dlp ..." otherwise, running the first package name as root
      return 1
  fi
  phase=purpose_setup
  while true; do
    load_dictionary
    if ! read -r -p "Enter a number [1-15]: " optionmenu; then
        caution "There is no more input to read, so no purpose profile was chosen and none was installed. Run this step again from a terminal, or use purpose=<name> in CARINO_SETUP_PLAN." # runPlan feeds this read a single number on stdin, so the end of that input has to be a clean return rather than a wildcard
        return 1
    fi
    case $optionmenu in
      #Basic
      1) 
          caution "Installing the Basic profile" # $1 inside a function is the function argument, not the script argument
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $postFlags
          flatpakInstall $basicFlatpak $googleFlatpak $microsoftFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Gaming
      2)
          caution "Installing the Gaming profile"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $gamingPackages $postFlags
          flatpakInstall $basicFlatpak $gamingFlatpak $googleFlatpak $microsoftFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Corporate
      3)
          caution "Installing the Corporate profile"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $ciscoPackages $postFlags
          flatpakInstall $googleFlatpak $microsoftFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Corporate (just Microsoft)
      4)
          caution "Installing the Corporate (Microsoft only) profile"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $postFlags
          flatpakInstall $basicFlatpak $microsoftFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Corporate (just Google)
      5)
          caution "Installing the Corporate (Google only) profile"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $postFlags
          flatpakInstall $basicFlatpak $googleFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Development
      6)
          caution "Installing the Development profile"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $developmentPackages $virtconPackages $postFlags
          flatpakInstall $basicFlatpak $googleFlatpak $developmentFlatpak $supportFlatpak $remoteSupportFlatpak
          distroboxContainers
          ;;
      #Astronomy
      7)
          caution "Installing the Astronomy profile"
          profileWarning "Astronomy" "$astronomyPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $astronomyPackages $postFlags
          flatpakInstall $basicFlatpak $googleFlatpak $astronomyFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Comp-Neuro
      8)
          caution "Installing the Computational Neuroscience profile"
          profileWarning "Computational Neuroscience" "$compneuroPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $compneuroPackages $postFlags
          flatpakInstall $basicFlatpak $compneuroFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Design
      9)
          caution "Installing the Design profile"
          profileWarning "Design" "$designPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $designPackages $postFlags
          flatpakInstall $basicFlatpak $designFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Music Production
      10)
          caution "Installing the Music Production profile"
          profileWarning "Music Production" "$musicPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $musicPackages $postFlags
          flatpakInstall $basicFlatpak $musicFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Cybersecurity
      11)
          caution "Installing the Cybersecurity profile"
          profileWarning "Cybersecurity" "$securityPackages"
          caution "hydra, hashcat, aircrack-ng, masscan and sqlmap are dual use tools, only run them against systems you are authorised to test, and add yourself to the wireshark group for capture without root." # the packages install cleanly either way, the constraint is legal rather than technical
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $securityPackages $postFlags
          flatpakInstall $basicFlatpak $securityFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Forensics
      12)
          caution "Installing the Forensics profile"
          profileWarning "Forensics" "$forensicsPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $forensicsPackages $postFlags
          flatpakInstall $basicFlatpak $supportFlatpak $remoteSupportFlatpak # no forensics specific Flatpak is shipped, the imaging and carving tools above are all native
          ;;
      #Scientific
      13)
          caution "Installing the Scientific profile"
          profileWarning "Scientific" "$scientificPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $scientificPackages $postFlags
          flatpakInstall $basicFlatpak $scientificFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Robotics
      14)
          caution "Installing the Robotics profile"
          profileWarning "Robotics" "$roboticsPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $roboticsPackages $postFlags
          flatpakInstall $basicFlatpak $roboticsFlatpak $developmentFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Medical Imaging
      15)
          caution "Installing the Medical Imaging profile"
          profileWarning "Medical Imaging" "$imagenologyPackages"
          sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $imagenologyPackages $postFlags
          flatpakInstall $basicFlatpak $imagenologyFlatpak $supportFlatpak $remoteSupportFlatpak
          ;;
      #Back to main menu
      16)
          caution "Returning to the main menu"
          ;; # displayMenu is the caller and it redraws itself now, so calling it back from here would nest one shell frame per round trip
      *)
          error "Bad input: '$optionmenu' is not one of 1-15. Please choose again."
          continue
          ;;
    esac # the printed list and the case bodies now line up one for one, picking a profile no longer reopens the main menu
    return 0 # every arm but the wildcard leaves the loop, a profile is installed once and the caller decides what happens next
  done
}
serverSetup ()
{
    if [[ -z "$pkgm" ]]; then
        error "No package manager was configured for '${DISTRIBUTION:-unknown}', the server setup cannot run here."
        return 1
    fi
    sudo $pkgm $updatePreFlags $argUpdate $updateFlags || { error "The package index could not be refreshed, so every server package below would be looked up against a stale or empty index. Nothing was installed."; return 1; } # preFlags is wrong here, apt rejects its -f on the update operation with exit 100 and then every name in the install line came back "Unable to locate package"; the hardcoded "update -y && upgrade -y" was an apt-ism, pacman has no update operation and zypper rejects -y, and postFlags cannot be reused here because the atomic family puts an install-only option in it
    [[ -n "$argUpgrade" ]] && sudo $pkgm $preFlags $argUpgrade $postFlags # apt is not the only one, zypper refresh upgraded nothing either and a server left on the packages it was imaged with is the whole thing this function is meant to prevent
    sudo $pkgm $preFlags $argInstall $essentialPackages $basicSystemPackages $serverPackages $developmentPackages $postFlags # preFlags has to precede the subcommand, zypper and every other pre-command family rejected it where it sat
}
techSetup ()
{
    caution $NAME
    if [[ -z "$pkgm" ]]; then
        error "No package manager was configured for '${DISTRIBUTION:-unknown}', so no repository or package work can be done here." # covers every distribution identifyDistro declined, the installs below would otherwise run as "sudo  install ..."
        return 1
    fi
    if [[ "$distroType" == "atomic" ]]; then
    caution "Atomic system detected, only the essential packages will be layered." # RPM Fusion, the codec swap and the -y flag do not apply to rpm-ostree, and the Universal Blue images already ship codecs and their driver akmods
    sudo $pkgm $argUpdate
    sudo $pkgm $preFlags $argInstall $essentialPackages $postFlags
    else
    case $NAME in
    *Fedora*|*Silverblue*|*Kinoite*|*Sericea*|*Onyx*)
    #DNF5 works fine, will drop dnf.conf related configs
    #if [ $(cat /etc/dnf/dnf.conf | grep fastestmirror=true) ]
    #  then
    #      echo ""
    #  else
    #      sudo sh -c 'echo fastestmirror=true >> /etc/dnf/dnf.conf' #Looks for the lowest ping, not necessarily the best bandwith
    #      sudo sh -c 'echo max_parallel_downloads=10 >> /etc/dnf/dnf.conf'
    #  fi 
    #sudo systemctl disable NetworkManager-wait-online.service
    caution "Installing RPM FUsion"
    if [ -f /etc/yum.repos.d/rpmfusion-free.repo ] || [ -f /etc/yum.repos.d/rpmfusion-nonfree.repo ]; then
        caution "RPM Fusion is installed already, moving on"
        else
        sudo $pkgm $argInstall https://mirror.fcix.net/rpmfusion/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://opencolo.mm.fcix.net/rpmfusion/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm fedora-workstation-repositories dnf-plugins-core -y
        updateGrub
    fi
    sudo $pkgm update -y && sudo $pkgm install $essentialPackages -y
    swapCodecsFedora # RPM Fusion is enabled above, so the crippled codec packages can be swapped for the freeworld ones
    ;;
    *Nobara*|*Risi*|*Ultramarine*|*Bazzite*|*Bluefin*|*Aurora*|*"Universal Blue"*)
    sudo $pkgm $argUpdate -y && sudo $pkgm install $essentialPackages -y
    updateGrub
    ;;
    *"Amazon Linux"*)
    sudo $pkgm $argUpdate -y && sudo $pkgm $preFlags $argInstall $essentialPackages $postFlags # no EPEL and no CRB exist here, so only what the Amazon repositories already carry can be installed
    ;;
    *CentOS*|*Rocky*|*AlmaLinux*|*"Oracle Linux"*|*EuroLinux*|*"Circle Linux"*|*Springdale*|*Anolis*|*OpenCloudOS*|*TencentOS*|*"Alibaba Cloud Linux"*|*CloudLinux*)
    info "Enabling CRB and EPEL"
    sudo $pkgm config-manager --set-enabled crb || sudo $pkgm config-manager --set-enabled powertools # crb on 9 and 10, powertools on 8; subscription-manager does not exist on the rebuilds
    sudo $pkgm $preFlags $argInstall epel-release $postFlags # without EPEL half of the desktop groups and fastfetch, i3, sway and budgie are in no enabled repository at all
    sudo $pkgm $argUpdate -y && sudo $pkgm $preFlags $argInstall $essentialPackages $postFlags # a bare -y skipped the family's own flags, so a single name that EPEL and CRB do not carry aborted the essential install on the one family whose repository set varies most between rebuilds
    updateGrub
    ;;
    *"Red Hat"*)
    caution "RHEL"
    sudo systemctl disable NetworkManager-wait-online.service
    info "Installing EPEL repo"
    rhelMajor=$(rpm -E %rhel 2>/dev/null) # derived at runtime, the README claims RHEL 9 and 10
    [[ "$rhelMajor" =~ ^[0-9]+$ ]] || rhelMajor="${VERSION%%.*}"
    sudo subscription-manager repos --enable codeready-builder-for-rhel-$rhelMajor-$(uname -m)-rpms
    sudo $pkgm $argInstall https://dl.fedoraproject.org/pub/epel/epel-release-latest-$rhelMajor.noarch.rpm -y
    info "Installing Essential Packages"
    sudo $pkgm $argInstall $essentialPackages $postFlags
    ;;
    *Debian*|*Ubuntu*|*Pop!_OS*|*"Linux Mint"*|*LMDE*|*Zorin*|*elementary*|*Kali*|*Parrot*|*Devuan*|*Raspbian*|*"Raspberry Pi OS"*|*MX*|*antiX*|*Deepin*|*deepin*|*"KDE neon"*|*Trisquel*|*PureOS*|*TUXEDO*|*PikaOS*|*Armbian*|*SparkyLinux*|*Q4OS*)
    sudo $pkgm $argUpdate -y && sudo $pkgm upgrade -y
    sudo $pkgm $argInstall $essentialPackages -y
    ;;
    *Arch*|*Manjaro*|*EndeavourOS*|*Garuda*|*CachyOS*|*ArcoLinux*|*RebornOS*|*Archcraft*)
    caution "Arch"
    sudo $pkgm $argUpdate $postFlags # a full -Syu has to come first, installing against a stale sync database on a rolling release gives 404s or a half upgraded system
    info "Installing Essential Packages"
    for archPackage in $essentialPackages; do sudo $pkgm $preFlags $argInstall $archPackage $postFlags || caution "$archPackage is not in the repositories, skipping it"; done # pacman has no --skip-broken, a single unknown name would abort the whole transaction
    updateGrub
    ;;
    *openSUSE*|*SUSE*|*SLES*|*SLED*)
    caution "openSUSE"
    sudo $pkgm $preFlags $argUpdate $postFlags
    sudo $pkgm $preFlags $argUpgrade $postFlags # the literal "update" was wrong on Tumbleweed and Slowroll, where zypper update holds back every package whose dependencies changed, which on a rolling snapshot is most of them; argUpgrade is dup there and update on Leap and SLE
    info "Installing Essential Packages"
    sudo $pkgm $preFlags $argInstall $essentialPackages $postFlags
    ;;
    *)
    error "Unsupported distribution: '${DISTRIBUTION:-unknown}' ${VERSION:-}. No repository or package work was done." # names what was detected instead of printing the bare string "2"
    ;;
    esac
    fi
    info "Troubleshooting DONE"
    flathubEnable # the bare exit that used to sit here made everything below unreachable
    desktopenvironment
    desktopStatus=$? # captured here because graphicDrivers below overwrites $?
    graphicDrivers
    #nvtopInstall
    [[ $desktopStatus -eq 0 ]] && finalTweaks
    return 0 # declining a desktop is not a failure of the technical setup, without this the test above would leak a non-zero status to the quick branch
}
#This functios in only for Fedora, might be adapted to other distros like openSUSE
swapCodecsFedora ()
{
    sudo $pkgm swap $preFlags ffmpeg-free ffmpeg $postFlags # named explicitly, awk field positions broke whenever essentialPackages was edited
    sudo $pkgm swap $preFlags mesa-va-drivers mesa-va-drivers-freeworld $postFlags
    sudo $pkgm swap $preFlags mesa-vdpau-drivers mesa-vdpau-drivers-freeworld $postFlags
    sudo $pkgm $argInstall $preFlags libavcodec-freeworld $postFlags
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
    caution "This replaces ~/.config/i3, ~/.fonts and ~/.icons with a third party dotfiles repository. Continue? [y/N]" # it used to overwrite an existing i3 configuration with no prompt and no backup
    if [[ "$NONINTERACTIVE" == 1 ]]; then option="n"; caution "Non-interactive run: taking the default [N], your i3 configuration is left untouched."; else read -r option; fi
    if [[ "$option" =~ ^[Yy]$ ]]; then
        i3Dotfiles="$HOME/.cache/carino-i3-dotfiles" # cloned into a known directory, the old form landed in $PWD while the copies below read from $HOME, so they silently failed unless the script was run from there
        rm -rf "$i3Dotfiles" && git clone https://gitlab.com/dajhub/i3-dotfiles.git "$i3Dotfiles" || caution "The i3 dotfiles could not be fetched, the existing configuration was left alone"
        i3Backup="$HOME/carino-i3-backup-$(date +%Y%m%d-%H%M%S)"
        if [[ -d "$i3Dotfiles/.config/i3" ]]; then
            mkdir -p "$i3Backup" && cp -r ~/.config/i3 ~/.fonts ~/.icons "$i3Backup"/ 2>/dev/null; success "Anything that existed was backed up to $i3Backup"
            cp -r "$i3Dotfiles/.config/i3/" ~/.config/
            cp -r "$i3Dotfiles/.fonts/" ~/
            cp -r "$i3Dotfiles/.icons/" ~/
        fi
    else
        caution "The i3 configuration was left untouched."
    fi
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
  if [[ -z "$pkgm" ]]; then
      error "No package manager was configured for '${DISTRIBUTION:-unknown}', nothing was updated."
      return 1
  fi
  sudo $pkgm $updatePreFlags $argUpdate $updateFlags || { error "The package index could not be refreshed, so nothing was updated. Read the package manager's message above."; return 1; } # preFlags is wrong here, apt rejects its -f on the update operation with exit 100 and refreshes nothing at all; the hardcoded -y meant --refresh to pacman and is not an option at all for zypper, and postFlags carries --allow-inactive on the atomic family, which rpm-ostree upgrade rejects
  if [[ -n "$argUpgrade" ]]; then sudo $pkgm $preFlags $argUpgrade $postFlags || { error "The upgrade failed, the package index was refreshed but no package was upgraded. Read the package manager's message above."; return 1; }; fi # apt and zypper both separate the index refresh from the package upgrade, and the openSUSE half of that was missing entirely, so this function refreshed metadata and then announced success having upgraded nothing; argUpgrade is empty on every family whose argUpdate already upgrades
  success "Your system has been updated" # only reached when both operations above succeeded, it used to be printed unconditionally and told the user a failed run had worked
}
# Declaring Packages
# Generic GNU/Linux Packages
# Essential packages are what will allow system review for advanced users and stable hardware experience
essentialPackages="pciutils git cmake wget nano curl jq elinks nasm lshw lm*sensors rsync rclone mediainfo cifs-utils ntfs-3g* lsof xinput procps git-lfs gnupg openssh-client* blktrace iotop smartmontools" #gcc-c++ lm_sensors.x86_64
# Server packages ensure SSH, FTP and RDP connectivity, so advanced users can configure and use the server remotely
serverPackages="netcat-traditional xserver-xorg-video-dummy openssh-server cockpit expect ftp vsftpd sshpass" # these are the Debian spellings, the RPM and openSUSE families replace the whole list below because netcat-traditional and xserver-xorg-video-dummy exist on neither
serverPackagesRPM="nmap-ncat xorg-x11-drv-dummy openssh-server cockpit expect ftp vsftpd sshpass"
serverPackagesOpenSUSE="netcat-openbsd xf86-video-dummy openssh cockpit expect ftp vsftpd sshpass"
# Basic packages will allow endusers to perform basic activities or get basic features
basicUserPackages="gedit yt-dlp ffmpeg* tumbler libreoffice pavucontrol vnstat feh flatpak" #fontawesome-fonts-all epiphany # Flatpak - clamav clamtk obs-studio transmission
basicSystemPackages="wine xrdp htop powertop *gtkglext* libxdo-* ncdu scrot xclip" # tldr moved out of the shared base, it is packaged on Fedora only and neither Debian trixie nor openSUSE carries that name
basicSystemPackagesRPM="tldr"
basicSystemPackagesOpenSUSE="wine xrdp htop powertop *gtkglext* xdotool ncdu scrot xclip tealdeer" # the shared list with libxdo-* spelled xdotool, and tealdeer is the tldr client here
basicDesktopEnvironmentPackages="nautilus fontawesome-fonts" # fontawesome-fonts resolves through fontawesome4-fonts on Fedora and exists verbatim on openSUSE, Debian spells it fonts-font-awesome and gets the override below
basicDesktopEnvironmentPackagesDebian="nautilus fonts-font-awesome"
# Gaming packages will allow enduseres to play on the most popular platforms
gamingPackages="goverlay"
# Multimedia pacakges allow the end user to use the most
multimediaPackages="gstreamer* gscan2pdf python3-qt* python3-vapoursynth qt5-qtbase-devel vapoursynth-* libqt5* libass*" #qt5-qtbase-devel python3-qt5 # Flatpak - gimp krita blender kdenlive
developmentPackages="gcc cargo npm python3-pip nodejs golang conda* ncurses-dev*"
virtconPackages="podman distrobox bridge-utils virt-manager virt-top"
virtconPackagesRPM="@virtualization libvirt libvirt-devel virt-install qemu-kvm qemu-img"
virtconPackagesDebian="libvirt-daemon-system libvirt-clients virtinst"
virtconPackagesOpenSUSE=""
supportPackages="xxd" #stacer barrier bleachbit filezilla bless #Flatpak - remmina bless
amdPackages="ocl-icd-dev* opencl-headers libdrm-dev* rocm*" #mesa-vdpau-drivers mesa-va-drivers
nvidiaPackages="vdpauinfo libva-utils vulkan nvidia-xconfig xorg-x11-drv-nvidia-cuda" # this list is RPM shaped and nothing but the rpm families reads it any more, debian, arch and opensuse all replace it; libva-vdpau-driver was dropped because it exists in no current Fedora and dnf5 aborts the entire transaction on an unmatched name even with --skip-broken (verified on fedora:44, "definitely-not-a-real-package" plus zsh installs neither), so the NVIDIA step got nothing at all on the one family this list is for #kernel-headers kernel-devel xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-cuda-libs
nvidiaPackagesRPM="akmod-nvidia libva-nvidia-driver" # RPM Fusion renamed nvidia-vaapi-driver, the old name resolves to nothing and --skip-broken dropped it silently so VA-API was simply never installed
nvidiaPackagesDebian="nvidia-driver nvidia-open-kernel-dkms firmware-nvidia-gsp nvidia-settings nvidia-vaapi-driver nvidia-smi linux-headers-amd64 vainfo vdpau-driver-all va-driver-all vulkan-tools" # every one of these needs contrib, non-free and non-free-firmware, which nvidiaRepoSetup enables; the old value was Fedora glob shaped (nvidia-driver*, nvidia-vulkan*) and nvidia-xconfig plus nvidia-vdpau-driver do not exist in trixie main at all. nvidia-driver pulls nvidia-driver-libs, libcuda1, nvidia-vdpau-driver, nvidia-egl-icd and xserver-xorg-video-nvidia by itself, and the open kernel module is chosen because the legacy one is being retired; verified with apt-get install -s on debian:trixie, zero E: lines
nvidiaPackagesUbuntu="ubuntu-drivers-common linux-headers-generic nvidia-vaapi-driver vainfo vdpau-driver-all va-driver-all vulkan-tools" # read by the ubuntu branch of the debian arm, it used to be read nowhere at all; Ubuntu spells the driver as version numbered metapackages (nvidia-driver-610 today, nvidia-driver-560 when the old value here was written) so a literal name here rots with every release, ubuntu-drivers install picks the one that matches the card instead
nvidiaPackagesOpenSUSE="nvidia-video-G06 nvidia-gl-G06 nvidia-compute-G06 nvidia-open-driver-G06-signed-kmp-default" # the OSS repository carries the signed kernel module only, the userspace libraries come from NVIDIA's own repository that nvidiaRepoSetup adds; verified to resolve on both opensuse/tumbleweed and opensuse/leap:16.0 with --auto-agree-with-licenses, which the G06 packages require

# Desktop Environment variables (I'm too drunk and lazy to setup arrays, sorry) Also, some packages will be repeating between variables. This solution could be way better. Once I integrate more distros will look into it.
fedoraxfcePackages="@xfce-desktop-environment"
fedoragnomePackages="@workstation-product-environment"
fedorakdePackages="@kde-desktop-environment"
fedoramatePackages="@mate-desktop-environment"
fedoracinnamonPackages="@cinnamon-desktop-environment"
fedoralxqtPackages="@lxqt-desktop-environment"
fedorai3Packages="@i3-desktop-environment"
fedoraopenboxPackages="@basic-desktop-environment"
fedorabudgiePackages="budgie-desktop"
fedoraswayPackages="sway"
fedorahyprlandPackages="hyprland xorg-x11-server-Xwayland waybar xdg-desktop-portal-hyprland hyprland-autoname-workspaces hyprpaper libdisplay-info libinput libliftoff hyprshot"
fedoraniriPackages="niri waybar"
fedoracosmicPackages="@cosmic-desktop"

rhelxfcePackages="@Xfce @base-x"
rhelgnomePackages="@gnome @base-x gnome-extensions"
rhelkdePackages="@kde @base-x"
rhelmatePackages=""
rhelcinnamonPackages=""
rhellxqtPackages=""
rheli3Packages=""
rhelopenboxPackages=""
rhelbudgiePackages=""
rhelswayPackages=""
rhelhyprlandPackages=""
rhelniriPackages=""

debianxfcePackages="task-xfce-desktop"
debiangnomePackages="task-gnome-desktop"
debiankdePackages="task-kde-desktop"
debianmatePackages="task-mate-desktop"
debiancinnamonPackages="task-cinnamon-desktop"
debianlxqtPackages="task-lxqt-desktop"
debiani3Packages="i3"
debianopenboxPackages="openbox"
debianbudgiePackages="budgie-desktop"
debianswayPackages="sway"
debianhyprlandPackages=""
debianniriPackages=""

opensusexfcePackages="patterns-xfce-xfce"
opensusegnomePackages="patterns-gnome-gnome"
opensusekdePackages="patterns-kde-kde"
opensusematePackages="patterns-mate-mate"
opensusecinnamonPackages="patterns-cinnamon-cinnamon"
opensuselxqtPackages="patterns-lxqt-lxqt"
opensusei3Packages="i3 dmenu i3status"
opensuseopenboxPackages="openbox"
opensusebudgiePackages="budgie-desktop"
opensuseswayPackages="sway"
opensusehyprlandPackages=""
opensuseniriPackages=""

centosxfcePackages="@xfce"
centosgnomePackages="@gnome"
centoskdePackages="@kde"
centosmatePackages="@mate"
centoscinnamonPackages="@cinnamon"
centoslxqtPackages="@lxqt"
centosi3Packages="i3"
centosopenboxPackages="openbox"
centosbudgiePackages="budgie-desktop"
centosswayPackages="sway xorg-x11-server-Xwayland waybar xdg-desktop-portal-wlr wl-clipboard"
centoshyprlandPackages="hyprland xorg-x11-server-Xwayland waybar xdg-desktop-portal-wlr libinput wl-clipboard hyprpaper"
centosniriPackages="niri waybar"

archgnomePackages="gnome gnome-tweaks gdm"
archxfcePackages="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
archkdePackages="plasma-meta sddm konsole dolphin"
archmatePackages="mate mate-extra lightdm lightdm-gtk-greeter"
archcinnamonPackages="cinnamon lightdm lightdm-gtk-greeter gnome-terminal"
archlxqtPackages="lxqt sddm breeze-icons"
archi3Packages="i3-wm i3status i3lock dmenu xorg-server xorg-xinit"
archopenboxPackages="openbox obconf-qt xorg-server xorg-xinit" # obconf was dropped from the repositories and the AUR, obconf-qt in extra replaces it
archbudgiePackages="budgie-desktop lightdm lightdm-gtk-greeter gnome-terminal"
archswayPackages="sway swaybg swayidle swaylock foot"
archhyprlandPackages="hyprland xdg-desktop-portal-hyprland waybar hyprpaper kitty xorg-xwayland"
archniriPackages="niri waybar fuzzel" # gnome, xfce4, xfce4-goodies, mate, mate-extra, lxqt and i3 are groups rather than packages, --noconfirm selects every member of them non-interactively

i3RicingPackages="rofi i3blocks picom kitty nitrogen lxappearance"
i3RicingPackagesArch="rofi i3blocks picom kitty lxappearance" # nitrogen is AUR only on Arch, and pacman aborts the whole i3 transaction on an unknown target

# Specific GNU/Linux Packages
intelPackages="intel-media-*driver"
basicSystemPackagesDebian="tealdeer" # neofetch is gone from Debian trixie and sid, and fastfetch is absent from Ubuntu noble, so neither replacement is safe across this family; tealdeer exists in both and provides the tldr command
essentialPackagesRPM="NetworkManager-tui NetworkManager xkill tigervnc-server dhcp-server fastfetch" # NetworkManager moved out of the shared list, Debian spells it network-manager in lowercase and the capitalised name resolves to nothing there
essentialPackagesDebian="network-manager build-essential manpages-dev net-tools x11-utils tigervnc-standalone-server tigervnc-common tightvncserver isc-dhcp-server" # software-properties-common was the first name in this list and it does not exist in Debian 13 trixie, so apt aborted the whole transaction with exit 100 and installed nothing, invisibly on Ubuntu where the name still resolves; add-apt-repository is called nowhere in this file so the name is simply gone rather than moved to an Ubuntu list. Every remaining name was checked to resolve in both debian:trixie and ubuntu:24.04 #libncurses5-dev libncursesw5-dev libgtkglext1 linux-headers-amd64 linux-image-amd64
essentialPackagesOpenSUSE="pciutils git cmake wget nano curl jq elinks nasm lshw sensors rsync rclone mediainfo cifs-utils ntfs-3g* lsof xinput procps git-lfs gnupg openssh-client* blktrace iotop smartmontools" # the shared list with lm*sensors spelled sensors, every name verified to resolve in both opensuse/tumbleweed and opensuse/leap:15.6
basicUserPackagesOpenSUSE="gedit yt-dlp ffmpeg tumbler libreoffice pavucontrol vnstat feh flatpak"
supportPackagesOpenSUSE="vim"
gamingPackagesOpenSUSE="" # goverlay is in Tumbleweed but not in Leap 15.6, so the Gaming profile here is the base packages plus the gaming Flatpaks
developmentPackagesOpenSUSE="gcc cargo npm python3-pip nodejs golang make"
essentialPackagesArch="pciutils git cmake wget nano curl jq nasm lshw rsync rclone mediainfo cifs-utils lsof git-lfs gnupg iotop smartmontools lm_sensors ntfs-3g openssh procps-ng networkmanager xorg-xinput xorg-xkill tigervnc fastfetch" # spelled out because pacman expands no wildcards, and it is a replacement rather than an addition: lm*sensors, ntfs-3g*, openssh-client*, procps, xinput and NetworkManager are all Debian or RPM spellings, and blktrace is AUR only so it is dropped rather than left to abort the single transaction serverSetup uses
basicUserPackagesArch="gedit yt-dlp ffmpeg tumbler libreoffice-fresh pavucontrol vnstat feh flatpak" # libreoffice itself is not a package on Arch, only libreoffice-fresh and libreoffice-still are
basicSystemPackagesArch="wine htop powertop tealdeer ncdu scrot xclip" # tldr is tealdeer here, and xrdp is AUR only so it is dropped rather than guessed at
basicDesktopEnvironmentPackagesArch="nautilus otf-font-awesome" # ttf-font-awesome is in neither the repositories nor the AUR, extra ships it as otf-font-awesome
serverPackagesArch="openbsd-netcat xf86-video-dummy openssh cockpit expect vsftpd sshpass"
developmentPackagesArch="gcc rust npm python-pip nodejs go ncurses" # cargo ships inside the rust package and conda is not in the official repositories
supportPackagesArch=""
intelPackagesArch="mesa vulkan-intel intel-media-driver libva-intel-driver"
virtconPackagesArch="podman distrobox virt-manager libvirt virt-install qemu-full qemu-img" # bridge-utils is AUR only on Arch and pacman aborts the whole transaction on an unknown target
amdPackagesRPM="xorg-x11-drv-amdgpu systemd-devel" #xorg-x11-dr*
amdPackagesDebian="xserver-xorg-video-amdgpu libsystemd-dev"
amdPackagesOpenSUSE="Mesa-dri libdrm_amdgpu1 Mesa-libva libvulkan_radeon xf86-video-amdgpu ocl-icd-devel opencl-headers vulkan-tools libva-utils" # this was empty and appended to the shared RPM list, so zypper received rocm*, which matches nothing on Leap 16.0 and aborts the whole transaction with exit 104; these nine names were verified to resolve on both opensuse/tumbleweed and opensuse/leap:16.0
amdPackagesArch="mesa vulkan-radeon xf86-video-amdgpu ocl-icd opencl-headers" # rocm* is a glob and the ROCm stack is split across a dozen real names, so the OpenCL loader and headers are installed instead
nvidiaPackagesArch="nvidia-open-dkms nvidia-utils nvidia-settings egl-wayland libva-nvidia-driver vulkan-icd-loader" # the dkms variant is used because Manjaro, CachyOS and Garuda ship kernels the plain nvidia package does not build against, and nvidia-dkms no longer exists in the repositories, extra ships nvidia-open-dkms in its place
fedoraPackages="mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld libavcodec-freeworld dnf-plugin-system-upgrade"
rhelPackages="mesa-dri-drivers libavcodec*" #mesa-vdpau-drivers
astronomyPackages="" # astropy and celestia were valid on no supported distro, the library is python3-astropy everywhere and celestia is gone from Fedora and Debian alike, the planetarium role is covered by org.stellarium.Stellarium in astronomyFlatpak
astronomyPackagesRPM="python3-astropy"
astronomyPackagesDebian="python3-astropy"
compneuroPackages="" # nest is the Fedora simulator and neuron the Debian one, they are different software rather than two spellings, so the lists cannot be aliased
compneuroPackagesRPM="nest python3-nest python3-nibabel python3-networkx python3-numpy python3-scipy python3-matplotlib python3-pandas python3-scikit-learn python3-h5py jupyterlab"
compneuroPackagesDebian="neuron python3-brian python3-nibabel python3-networkx python3-numpy python3-scipy python3-matplotlib python3-pandas python3-sklearn python3-h5py jupyter-notebook"
designPackages="" # the GUI editors are Flatpaks, only the command line imaging and font tools come from the distribution
designPackagesRPM="ImageMagick GraphicsMagick optipng fontforge gmic"
designPackagesDebian="imagemagick graphicsmagick optipng fontforge gmic"
musicPackages="" # ardour is version suffixed on Fedora and musescore is musescore3 on Debian, so both are taken from Flathub instead of guessing a name
musicPackagesRPM="audacity lmms hydrogen mixxx qjackctl a2jmidid calf lsp-plugins guitarix fluidsynth qsynth"
musicPackagesDebian="audacity lmms hydrogen mixxx qjackctl a2jmidid calf-plugins lsp-plugins x42-plugins guitarix fluidsynth qsynth"
securityPackages="" # nikto is left out on purpose, it exists only in the Debian non-free component which a stock sources.list does not enable, and not at all on Fedora
securityPackagesRPM="nmap wireshark tcpdump nmap-ncat john hydra aircrack-ng hashcat masscan binwalk yara whois bind-utils"
securityPackagesDebian="nmap zenmap wireshark tshark tcpdump netcat-openbsd john hydra aircrack-ng hashcat masscan binwalk yara whois bind9-dnsutils sqlmap"
forensicsPackages="" # autopsy, scalpel, safecopy, hashdeep and the aff tools are packaged on Debian only, the asymmetry between the two lists is deliberate
forensicsPackagesRPM="sleuthkit testdisk foremost ewftools dc3dd ddrescue chkrootkit rkhunter perl-Image-ExifTool binwalk yara"
forensicsPackagesDebian="sleuthkit autopsy testdisk foremost ewf-tools afflib-tools scalpel safecopy hashdeep dc3dd gddrescue chkrootkit rkhunter libimage-exiftool-perl binwalk yara"
scientificPackages="" # paraview and the texlive collection dominate the download size, drop them from the lists below if the profile has to stay small
scientificPackagesRPM="octave gnuplot maxima wxMaxima R-core python3-numpy python3-scipy python3-matplotlib python3-pandas python3-sympy python3-scikit-learn python3-h5py jupyterlab paraview gmsh texlive-collection-latexrecommended"
scientificPackagesDebian="octave gnuplot-qt maxima wxmaxima r-base python3-numpy python3-scipy python3-matplotlib python3-pandas python3-sympy python3-sklearn python3-h5py jupyter-notebook paraview gmsh texlive-latex-recommended"
roboticsPackages="" # platformio is packaged on Fedora only, on Debian it ships through pip which this script deliberately does not use
roboticsPackagesRPM="avr-gcc avr-libc avrdude stlink dfu-util minicom picocom python3-pyserial esptool openscad kicad platformio"
roboticsPackagesDebian="gcc-avr avr-libc avrdude stlink-tools dfu-util minicom picocom python3-serial esptool openscad kicad"
# Corporate Packages
#remoteSupportPackages="anydesk"
rustdesk="https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-0.x86_64.rpm https://github.com/rustdesk/rustdesk/releases/download/1.3.2/rustdesk-1.3.2-x86_64.deb" #Taken from https://github.com/rustdesk/rustdesk/releases/
#microsoftPackages="microsoft-edge-stable code" #powershell
zoom="https://zoom.us/client/latest/zoom_x86_64.rpm"
#googlePackages="https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"
ciscoPackages="https://binaries.webex.com/WebexDesktop-CentOS-Official-Package/Webex.rpm vpnc"
ciscoPackagesArch="vpnc" # Webex ships an RPM and a DEB only, on Arch it is a Flatpak or nothing
# CustomPackages
languagePackages="fcitx5 fcitx5-mozc"
carinoPackages="lpf-spotify-client telegram-desktop texlive-scheme-full"
# Flatpak packages
basicFlatpak="org.mozilla.Thunderbird io.mpv.Mpv com.gitlab.davem.ClamTk com.obsproject.Studio com.transmissionbt.Transmission"
multimediaFlatpak="org.gimp.GIMP org.kde.krita org.blender.Blender org.kde.kdenlive "
gamingFlatpak="com.valvesoftware.Steam net.davidotek.pupgui2 com.heroicgameslauncher.hgl com.discordapp.Discord net.lutris.Lutris"
developmentFlatpak="io.podman_desktop.PodmanDesktop"
googleFlatpak="com.google.Chrome"
microsoftFlatpak="com.microsoft.Edge com.visualstudio.code com.github.IsmaelMartinez.teams_for_linux"
corporateFlatpak="org.onlyoffice.desktopeditors "
supportFlatpak="com.github.tchx84.Flatseal org.keepassxc.KeePassXC org.remmina.Remmina com.github.afrantzis.Bless"
remoteSupportFlatpak="com.anydesk.Anydesk com.rustdesk.RustDesk"
astronomyFlatpak="org.kde.kstars org.siril.Siril org.stellarium.Stellarium"
compneuroFlatpak="io.github.nest_desktop.nest-desktop org.spyder_ide.spyder"
designFlatpak="org.gimp.GIMP org.inkscape.Inkscape org.kde.krita org.blender.Blender net.scribus.Scribus org.darktable.Darktable"
musicFlatpak="org.ardour.Ardour org.musescore.MuseScore"
securityFlatpak="org.zaproxy.ZAP org.ghidra_sre.Ghidra"
scientificFlatpak="org.spyder_ide.spyder org.scilab.Scilab"
imagenologyPackages="dcmtk xmedcon dcm2niix python3-gdcm python3-pydicom python3-nibabel" # verified in fedora:latest and debian:trixie containers, the two names that differ per family are appended by identifyDistro
imagenologyPackagesRPM="gdcm python3-pynetdicom" # python3-pynetdicom has no Debian package and gdcm is spelled libgdcm-tools there
imagenologyPackagesDebian="libgdcm-tools"
imagenologyFlatpak="io.github.nroduit.Weasis com.github.AlizaMedicalImaging.AlizaMS br.gov.cti.invesalius" # Weasis is the reference open source DICOM viewer, Aliza MS is a lighter one, InVesalius does 3D reconstruction from CT and MR
roboticsFlatpak="org.freecad.FreeCAD cc.arduino.IDE2" # freecad is in no Fedora repository and the packaged Arduino IDE is the deprecated 1.x, and the Flathub id is cc.arduino.IDE2 rather than io.github.arduino.IDE2
# Pending packages for review
# libadwaita-devel libXtst-devel libX11-devel samba samba-client samba-common minigalaxy
planPurposeNames="basic gaming corporate corporate-microsoft corporate-google development astronomy compneuro design music cybersecurity forensics scientific robotics"
planDesktopNames="gnome xfce kde lxqt cinnamon mate i3 openbox budgie sway hyprland niri none"
planDirectiveNames="technical, purpose=<name>, desktop=<name>, drivers, update, server, reboot=yes|no"
planPurposeNumber ()
{
    case "$1" in # the plan speaks names only, this is the single place where a name becomes the number purposeMenu reads, so renumbering that menu means editing this map and nothing else
        basic) echo 1 ;;
        gaming) echo 2 ;;
        corporate) echo 3 ;;
        corporate-microsoft) echo 4 ;;
        corporate-google) echo 5 ;;
        development) echo 6 ;;
        astronomy) echo 7 ;;
        compneuro) echo 8 ;;
        design) echo 9 ;;
        music) echo 10 ;;
        cybersecurity) echo 11 ;;
        forensics) echo 12 ;;
        scientific) echo 13 ;;
        robotics) echo 14 ;;
        imagenology) echo 15 ;;
        *) return 1 ;;
    esac
}
planDesktopKnown ()
{
    case " $planDesktopNames " in *" $1 "*) return 0 ;; *) return 1 ;; esac # installDesktopEnvironment is already keyed by name, so the desktop half of a plan needs no number at all
}
planInstallDesktop ()
{
    case "$1" in # the extra package arguments mirror the arms of desktopenvironmentMenu one for one, the menu is bypassed rather than fed because a plan draws no menu and reads no input
        none) caution "Plan step: desktop none, no desktop environment will be installed."; return 1 ;;
        xfce|sway|hyprland) installDesktopEnvironment "$1" $basicDesktopEnvironmentPackages ;;
        i3) installDesktopEnvironment i3 $i3RicingPackages $basicDesktopEnvironmentPackages ;;
        niri) niriRepo; installDesktopEnvironment niri $basicDesktopEnvironmentPackages ;; # niri lives in a copr on Fedora, the repo has to be enabled before installing
        *) installDesktopEnvironment "$1" ;;
    esac
}
planValidate ()
{
    local directive name
    planReboot="no" # the contract's default, an absent reboot= directive is not a reboot
    planSteps=()
    IFS=',' read -ra planTokens <<< "${CARINO_SETUP_PLAN//$'\n'/,}" # read stops at the first newline, so a plan wrapped across lines by a mail client or a copy out of the builder page silently lost every directive after the first one, including an invalid name P2 has to refuse; newlines become separators rather than terminators
    for directive in "${planTokens[@]}"; do
        directive="${directive//[[:space:]]/}" # a plan pasted out of a browser can carry stray spaces, no directive or name contains one
        [[ -z "$directive" ]] && continue
        case "$directive" in
            technical|drivers|update|server) planSteps+=("$directive") ;;
            purpose=*)
                name="${directive#purpose=}"
                planPurposeNumber "$name" >/dev/null || { error "CARINO_SETUP_PLAN: '$name' is not a purpose name. Valid purposes: $planPurposeNames"; return 1; }
                planSteps+=("$directive")
                ;;
            desktop=*)
                name="${directive#desktop=}"
                planDesktopKnown "$name" || { error "CARINO_SETUP_PLAN: '$name' is not a desktop name. Valid desktops: $planDesktopNames"; return 1; }
                planSteps+=("$directive")
                ;;
            reboot=yes|reboot=no) planReboot="${directive#reboot=}" ;;
            reboot=*) error "CARINO_SETUP_PLAN: '$directive' is not valid, reboot takes yes or no."; return 1 ;;
            *) error "CARINO_SETUP_PLAN: '$directive' is not a directive. Valid directives: $planDirectiveNames"; return 1 ;;
        esac
    done
    if [[ ${#planSteps[@]} -eq 0 ]]; then
        error "CARINO_SETUP_PLAN names no action to take. Valid directives: $planDirectiveNames"
        return 1
    fi
    return 0
}
runPlan ()
{
    local directive
    NONINTERACTIVE=1 # set before anything else so a refusal, a prompt or a menu below can never block on stdin
    identifyDistro # detection first, exactly as the menu does it, a plan is a request rather than an override
    if [[ -z "$pkgm" ]]; then
        error "'${DISTRIBUTION:-unknown}' ${VERSION:-} is not supported, so CARINO_SETUP_PLAN was refused and nothing was installed."
        return 1
    fi
    planValidate || return 1 # the whole plan is parsed and checked before the first package is installed, so a typo in the third directive cannot leave a half configured machine
    info "Plan accepted, running non-interactively: $CARINO_SETUP_PLAN"
    for directive in "${planSteps[@]}"; do
        case "$directive" in
            technical) caution "Plan step: technical"; techSetup ;;
            purpose=*) caution "Plan step: purpose ${directive#purpose=}"; purposeMenu <<< "$(planPurposeNumber "${directive#purpose=}")" ;; # the selection is fed to the menu's own read, so the profile that runs is the one the menu defines and nothing is duplicated here
            desktop=*) caution "Plan step: desktop ${directive#desktop=}"; planInstallDesktop "${directive#desktop=}" && finalTweaks ;; # the tweaks follow an installed desktop, exactly as menu option 3 does
            drivers) caution "Plan step: drivers"; graphicDrivers ;;
            update) caution "Plan step: update"; updateSystem ;;
            server) caution "Plan step: server"; serverSetup ;;
        esac
    done
    success "CARINO_SETUP_PLAN has finished."
    askReboot # honours reboot=yes|no, and prints which default it took
    return 0
}
detectArgument() {
    identifyDistro # detection has to run for every branch, otherwise $pkgm, $family and $postFlags stay empty
    case "$1" in
        quick)
            techSetup || return 1 # techSetup returns 1 on a distribution it declined, without this the install below runs as "sudo  gedit ..."
            sudo $pkgm $preFlags $argInstall $basicUserPackages $basicSystemPackages $supportPackages $postFlags
            flatpakInstall $basicFlatpak $googleFlatpak
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
        svp)
            installSVP
            ;;
        simple)
            techSetup
            ;;
        server)
            serverSetup # the README states the server setup deliberately skips the full technical setup
            ;;
        distrobox)
            [[ -z "$pkgm" ]] && { error "No package manager was configured for '${DISTRIBUTION:-unknown}', the distrobox containers were not created here."; return 1; } # the same refusal every other arm inherits from the function it calls, distroboxContainers had none of its own
            distroboxContainers
            ;;
        desktop)
            desktopenvironmentMenu
            ;;
        anydesk)
            [[ -z "$pkgm" ]] && { error "No package manager was configured for '${DISTRIBUTION:-unknown}', AnyDesk cannot be installed here."; return 1; } # without it the line below runs as "sudo  install flatpak -y"
            sudo $pkgm $argInstall flatpak -y # flatpak has to exist before flathubEnable can add a remote with it
            flathubEnable
            flatpakInstall $remoteSupportFlatpak
            ;;
        anydesk-repo)
            anydeskRepo
            ;;
        librewolf)
            librewolfRepo
            ;;
        share)
            sharedFolder
            ;;
        proton)
            installproton
            ;;
        *)
            systemFacts # facts and menu strings are built after detection, never at file top level
            buildMenus
            displayMenu
            ;;
    esac
}
enableDryRun ()
{
    dryBin=$(mktemp -d) # a PATH shim rather than shell function overrides, because distrobox-create and mount.cifs are not portable function names
    dryChmod=$(command -v chmod); dryRm=$(command -v rm) # resolved to absolute paths while chmod and rm are still the real ones, the loop has to make its own shims executable and the trap has to delete the shim directory afterwards, and both of those names are shimmed below
    trap '"$dryRm" -rf "$dryBin"' EXIT
    for cmd in sudo flatpak wget git gsettings xdg-mime distrobox-create usermod modprobe hostnamectl mount.cifs subscription-manager mkdir rm cp mv ln tar bunzip2 chmod tee sed; do printf '#!/bin/bash\necho "DRY-RUN: %s $*"\nexit 0\n' "$cmd" > "$dryBin/$cmd"; "$dryChmod" +x "$dryBin/$cmd"; done # the mutating coreutils are shimmed too, without them a rehearsal really created ~/.steam/root/compatibilitytools.d and ~/WinFiles and really ran rm against a glob in the working directory; rpm-ostree and systemctl stay absent, both are only ever reached through sudo and rpm-ostree is command -v probed to detect an atomic system, so shimming it would make every Fedora look like Silverblue
    PATH="$dryBin:$PATH" # detection commands such as lspci, uname, curl and grep are deliberately left real, only the privileged and mutating calls are intercepted
    unset -f sudo # setupPrivilege may have defined sudo as a function for a root, doas or run0 system, and a function would take precedence over the shim above
    caution "DRY RUN: nothing below will actually run. Every privileged or system-modifying command is printed instead."
}
if ! setupPrivilege && [[ "$DRYRUN" != 1 ]]; then exit 1; fi # a real run that cannot elevate stops here rather than failing line by line while printing progress, a rehearsal is still allowed because the shim below provides sudo
[[ "$DRYRUN" == 1 ]] && enableDryRun
if [[ -n "$CARINO_SETUP_PLAN" ]]; then
    if [[ -n "$1" ]]; then error "CARINO_SETUP_PLAN and the argument '$1' were both given. Run one or the other, they are two ways of asking for the same work."; exit 1; fi
    runPlan; exit $? # the plan runs instead of the menu and the script ends here, it never falls through into displayMenu
fi
detectArgument "$1"
