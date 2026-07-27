#Carino Setup - Microsoft Windows - https://setup.carino.systems
#Remember to Set-ExecutionPolicy Bypass -Scope Process -Force
Write-Host "Remember to Set-ExecutionPolicy Bypass -Scope Process -Force"
#Defining variables
$wingetFlags=@("--exact","--silent","--accept-source-agreements","--accept-package-agreements","--disable-interactivity")   # every install runs unattended, a single prompt inside the loop would hang the whole script
#Defining functions
function info($message){ Write-Host $message -ForegroundColor Cyan }
function error($message){ Write-Host $message -ForegroundColor Red }
function caution($message){ Write-Host $message -ForegroundColor Yellow }
function success($message){ Write-Host $message -ForegroundColor Green }
function isElevated{
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)   # registry writes, module installation and Windows Update all need the administrator token
}
function interactiveUserSid{
    $explorer=Get-CimInstance Win32_Process -Filter "name='explorer.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1   # the shell process belongs to whoever is actually logged in, which is not always who accepted the UAC prompt
    if (-not $explorer) { return $null }   # no interactive desktop at all, nothing to compare against
    try { return (Invoke-CimMethod -InputObject $explorer -MethodName GetOwnerSid -ErrorAction Stop).Sid }   # SID rather than account name so a renamed or domain qualified account still compares correctly
    catch { return $null }
}
function setRegistry($path,$name,$value,$type="DWord"){
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }   # on a fresh install the key itself can be missing, not only the value
    try { New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null }   # -Force creates the value when it is absent and overwrites it when it is present, Set-ItemProperty only did the second
    catch { caution "Could not write $name under $path" }   # one failed tweak must not abort the remaining ones
}
function setwindowsUpdate{
    #Preparing Update Module
    Register-PSRepository -Default -ErrorAction SilentlyContinue   # the default repository is already registered on most systems and would throw otherwise
    Get-PSRepository
    Install-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue | Out-Null   # PSGallery cannot install anything without NuGet and would prompt for it
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false   # -Force also silences the untrusted repository confirmation
    Get-Package -Name PSWindowsUpdate
    Import-Module PSWindowsUpdate -Force
    #Update Windows and leave the reboot to the user
    info "Installing Windows Updates..."
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot   # -AutoReboot used to restart the machine before the packages were installed, this step is now last and the reboot is the user's decision
    caution "Some updates may need a reboot to finish, restart when convenient."
    ###Other Windows Update commands
    #Get-WindowsUpdate -AcceptAll -Install -AutoReboot
    #Get-WindowsUpdate -Install -KBArticleID KB5017308
    #Get-WUHistory
    #Remove-WindowsUpdate -KBArticleID KB5017308 -NoRestart
    #$HideList = "KB5017308"
    #Get-WindowsUpdate -KBArticleID $HideList –Hide
    #Show-WindowsUpdate -KBArticleID $HideList
}
function windows10tweaks{
    #Dark Theme
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" 0
    #Hiding unwanted taskbar elements
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "SearchBoxTaskbarMode" 0
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" "ShellFeedsTaskbarViewMode" 2
    #Does not add 'Shortcut' to new shortcuts
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "link" ([byte[]](0,0,0,0)) "Binary"   # REG_BINARY 00000000 on the caller's own hive, the old REG ADD line was batch syntax and wrote to a key literally named %1
    #Stops explorer to load changes
    Stop-Process -name explorer -force
    #Installing WSL distributions
    #wsl --install -d Ubuntu
    #wsl --install -d Debian
}
function windows11tweaks{
    ###How to add a new registry property, otherwise, modify them following the rest of commands in the function
    #New-itemproperty "HKLM:\Default\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value "0" -PropertyType Dword
    #Dark Theme
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" 0
    # Removes Search button from the Taskbar
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "SearchBoxTaskbarMode" 0
    # Removes Task View from the Taskbar
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0
    # Removes Widgets from the Taskbar
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
    # Removes Chat from the Taskbar
    setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" 0
    # Default StartMenu alignment 0=Left
    #setRegistry "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" 0
    #Stops explorer to load changes
    Stop-Process -name explorer -force
}

function installPackages {

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        error "winget was not found. Install App Installer from the Microsoft Store and run this script again."   # checked once here instead of failing on every package of the loop
        return
    }
    $b=Read-Host -Prompt "Now you must choose for a use case profile`nPlease select an option:`n1. Basic profile. For the most basic use cases like media playback, internet browsing, office suite, file manipulation, communication and remote assistance. `n2. Gaming profile. Is Basic profile plus popular gaming platforms and utilities, like Steam. `n3. Corporate profile. Delivers the most packages for office work, videocalls, including applications for specific working ecosystems like Microsoft's, Google's and Cisco's.`n4. FOSS profile. Open source applications only, for general use cases. No Steam and no proprietary browsers here.`n5. Personal profile. The author's own workstation set, with multimedia creation, containers, database and general utilities.`n6. Exit`n"
    #Installing packages
    switch ($b)
    {
       "1" {
        info "Installing packages..."
    (
        "KDE.Okular",
        "Google.Chrome",
        "CodecGuide.K-LiteCodecPack.Mega",
        "AdrienAllard.FileConverter",
        "7zip.7zip",
        "OBSProject.OBSStudio",
        "Oracle.JavaRuntimeEnvironment",
        #"Mozilla.Thunderbird",
        "AnyDeskSoftwareGmbH.AnyDesk",
        "RustDesk.RustDesk",
        #"Telegram.TelegramDesktop",
        #"TheDocumentFoundation.LibreOffice",
        #"KeePassXCTeam.KeePassXC",
        #"Git.Git"
        "ONLYOFFICE.DesktopEditors"
    ) | foreach {winget install --id $_ @wingetFlags}
       }
       "2" {#Probably can execute basic case then gaming to avoid repeating so many packages
        info "Installing packages..."
    (
        "CodecGuide.K-LiteCodecPack.Mega",
        "KDE.Okular.Nightly",
        "Spotify.Spotify",
        "AdrienAllard.FileConverter",
        "7zip.7zip",
        "Oracle.JavaRuntimeEnvironment",
        #"Mozilla.Thunderbird",
        "ventoy.Ventoy",
        "RustDesk.RustDesk",
        #"Telegram.TelegramDesktop",
        "TheDocumentFoundation.LibreOffice",
        "Valve.Steam",
        "OBSProject.OBSStudio",
        "Mumble.Mumble.Client"
    ) | foreach {winget install --id $_ @wingetFlags}
       }
       "3" {
        info "Installing packages..."
    (
        "Cisco.WebexTeams",
        "KDE.Okular.Nightly",
        "Google.Chrome",
        "Google.Drive",
        "CodecGuide.K-LiteCodecPack.Mega",
        "AdrienAllard.FileConverter",
        "7zip.7zip",
        #"ventoy.Ventoy",
        "OBSProject.OBSStudio",
        "Oracle.JavaRuntimeEnvironment",
        #"Mozilla.Thunderbird",
        "AnyDeskSoftwareGmbH.AnyDesk",
        "RustDesk.RustDesk",
        #"Telegram.TelegramDesktop",
        #"TheDocumentFoundation.LibreOffice",
        "KeePassXCTeam.KeePassXC",
        #"Git.Git"
        "ONLYOFFICE.DesktopEditors",
        "Fortinet.FortiClientVPN",
        "Mozilla.Firefox.ESR",
        "NSSM.NSSM",
        "ActivityWatch.ActivityWatch"
    ) | foreach {winget install --id $_ @wingetFlags}
       }
       "4" {
        info "Installing packages..."
    (
        "KDE.Okular.Nightly",
        "AdrienAllard.FileConverter",
        "7zip.7zip",
        "ventoy.Ventoy",
        "OBSProject.OBSStudio",
        #"Mozilla.Thunderbird",
        "RustDesk.RustDesk",
        "Telegram.TelegramDesktop",
        "TheDocumentFoundation.LibreOffice",
        "Mumble.Mumble.Client",
        "VSCodium.VSCodium",   # the MIT licensed build, Microsoft.VisualStudioCode ships under proprietary licence terms and does not belong in a FOSS only profile
        "KeePassXCTeam.KeePassXC",
        "SleuthKit.Autopsy",
        "StrawberryPerl.StrawberryPerl",
        "mRemoteNG.mRemoteNG",
        "Git.Git",
        "Python.Python.3.11",
        "qBittorrent.qBittorrent"

    ) | foreach {winget install --id $_ @wingetFlags}
       }
       "5" {
         info "Installing packages..."
    (
        "CodecGuide.K-LiteCodecPack.Mega",
        "KDE.Okular.Nightly",
        "AdrienAllard.FileConverter",
        "7zip.7zip",
        "dbeaver.dbeaver",
        "Espanso.Espanso",
        "Gyan.FFmpeg",
        "GIMP.GIMP",
        "KDE.Kdenlive",
        "Oracle.JavaRuntimeEnvironment",
        #"Mozilla.Thunderbird",
        "AnyDeskSoftwareGmbH.AnyDesk",
        "ventoy.Ventoy",
        "RustDesk.RustDesk",
        "OBSProject.OBSStudio",
        "Google.Chrome",
        #"Telegram.TelegramDesktop",
        "TheDocumentFoundation.LibreOffice",
        "qBittorrent.qBittorrent",
        "Mozilla.Thunderbird",
        "KDE.Okular",
        "RedHat.Podman",
        "RedHat.Podman-Desktop",
        "KeePassXCTeam.KeePassXC",
        "Microsoft.VisualStudioCode"
        #"Spotify.Spotify"
    ) | foreach {winget install --id $_ @wingetFlags}
       }
       "6" {
        caution "Exit"
        exit 0   # the menu offers this as the way out, returning instead would fall through to Register-PSRepository and Install-WindowsUpdate against the machine
       }
       Default {
        caution "Nothing will be installed"
        exit 0   # an unrecognised key is not consent to run Windows Update either
       }
    }
}

#Selecting case
Write-Host "Carino Setup - Microsoft Windows"
#Read-Host -Prompt "Welcome $env:username`nPlease select an option:`n1. Setup for Workstation`n2. Setup for Server`n3. Update my Windows System`n4. Install Video Drivers`n"
if (-not (isElevated)) {
    error "This script needs administrator rights. Reopen PowerShell as Administrator and run it again."   # failing here beats half applying tweaks, modules and updates
    exit 1
}
$callerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value   # the account whose token this process runs under, and therefore the hive HKCU: resolves to
$shellSid=interactiveUserSid
if ($shellSid -and $shellSid -ne $callerSid) {
    caution "You elevated with a different account than the one logged in at the desktop."   # standard user plus a separate admin credential is the normal way this happens
    caution "Every HKCU tweak and every winget user scope install would land in the elevating account's profile, so the desktop you are looking at would see no change while its explorer is still restarted."
    if ((Read-Host -Prompt "Type Y to continue anyway, anything else quits") -notmatch '^[Yy]$') { exit 1 }   # a silent no-op across two profiles is worse than stopping here
}
#Getting Windows Version
$windowsInfo=Get-CimInstance Win32_OperatingSystem   # queried once, the old script asked for the same data twice
$windowsVersion=$windowsInfo.Version
$windowsBuild=[int]$windowsInfo.BuildNumber   # compared as a number so new feature updates keep matching without editing the script
info "Your current Windows version is $windowsVersion (build $windowsBuild)"
switch ($windowsBuild)
{
 {$_ -ge 22000} {
    success "Basic profile for Windows 11"
    windows11tweaks
    installPackages
    setwindowsUpdate   # updates go last, they can schedule a reboot and nothing must be installed after that
    break   # both build clauses match on Windows 11, break keeps the Windows 10 one from running too
}
 {$_ -ge 10240} {
    success "Basic profile for Windows 10"
    windows10tweaks
    installPackages
    setwindowsUpdate
    break
}
 Default {error "Build $windowsBuild is older than Windows 10 (10240) and is not supported."}
}
#Setting up a new hostname
#Write-Host "Please, provide a name for your computer:"
#ForegroundColor Green
#$ComputerName = Read-Host
#Rename-Computer -NewName "$ComputerName"

Write-Host "Finished."
