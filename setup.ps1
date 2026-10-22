# ==== 0. Header ====
# Carino SimpleSetup for Windows 10 and 11: checks the system, installs the base apps and drivers
# with winget, applies a few Explorer tweaks, offers purpose profiles and runs Windows Update.
#
# Run from an elevated PowerShell (Windows PowerShell 5.1 or PowerShell 7):
#   iwr -useb https://setup.carino.systems/setup.ps1 | iex                         interactive
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1                           from a checkout
#   $env:CARINO_SETUP_DRYRUN='1'; iwr -useb https://setup.carino.systems/setup.ps1 | iex     print, change nothing
#   $env:CARINO_SETUP_PLAN='technical,tweaks,purpose=gaming,update,reboot=no'; ...           unattended
# Environment: CARINO_SETUP_DRYRUN=1, CARINO_SETUP_PLAN=<tokens>, CARINO_SETUP_LOG=<file>.
# Plan tokens: technical drivers tweaks update wsl purpose=<name> (may repeat) reboot=yes|no
# Test hook: CARINO_SETUP_FAKE=1 skips the Windows queries and uses CARINO_SETUP_BUILD (26100),
#            CARINO_SETUP_GPU ("nvidia amd intel"), CARINO_SETUP_VIRT (none|kvm|vmware|...), CARINO_SETUP_ARCH.
# Licence: AGPL-3.0-or-later, see LICENSE. Source: https://github.com/MiguelCarino/SimpleSetup

$CarinoSetup = {   # the whole script runs in this scope of its own: under "iwr | iex" nothing crosses to or from the caller
    Set-StrictMode -Off   # a caller's StrictMode would otherwise apply here too

    # ==== 1. Settings ====
    $DRYRUN = $env:CARINO_SETUP_DRYRUN -eq '1'
    $FAKE = $env:CARINO_SETUP_FAKE -eq '1'
    if ($FAKE) { $DRYRUN = $true }   # made-up facts must never drive real changes
    $PLAN = [string]$env:CARINO_SETUP_PLAN
    $NONINTERACTIVE = ($PLAN -ne '') -or [Console]::IsInputRedirected
    # run state lives in hashtables: functions change their members, which works in any scope
    $STATE = @{ Tokens = @(); Reboot = ''; NeedReboot = $false; ExitCode = 0; Log = '' }
    $RESULTS = New-Object System.Collections.ArrayList
    $DONE = @{}
    $SYS = @{}
    $WINGET_FLAGS = @('--exact', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    # winget exit codes that mean the package is there: 0x8A15002B no applicable update, 0x8A150061 already
    # installed, 0x8A15010D another version installed, 0x8A15010E a higher version installed
    $WINGET_OK = @(0, -1978335189, -1978335135, -1978334963, -1978334962)
    $WINGET_REBOOT = @(-1978334967, -1978334965)   # 0x8A150109 / 0x8A15010B: installed, finishes after a restart
    # Windows PowerShell 5.1 on older builds defaults to TLS 1.0, which PSGallery and GitHub refuse
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    # ==== 2. Helpers ====
    function say($m)    { Write-Host "==> $m" -ForegroundColor Cyan }
    function warn($m)   { Write-Host " !! $m" -ForegroundColor Yellow }
    function fail($m)   { Write-Host " xx $m" -ForegroundColor Red }
    function banner($m) { Write-Host ''; Write-Host "==== $m ====" -ForegroundColor Cyan }
    function record($status, $what) { [void]$RESULTS.Add("$status|$what") }   # record ok|fail|skip "what"
    function hex($code) { '0x{0:X8}' -f [int]$code }
    function refuse($why, $hint) {
        fail $why
        if ($hint) { Write-Host $hint }
        fail 'This system was refused and nothing was installed.'
        throw 'carino-refused'
    }

    function run([string]$runText, [scriptblock]$runAction) { # prints the command, runs it unless dry-run; returns its exit code
        if ($DRYRUN) { Write-Host "   (dry-run) > $runText" -ForegroundColor DarkGray; return 0 }
        Write-Host "   > $runText" -ForegroundColor DarkGray
        $global:LASTEXITCODE = 0
        try { & $runAction | Out-Host } catch { warn "$_"; return 1 }   # Out-Host also puts native output into the transcript
        if ($LASTEXITCODE) { return [int]$LASTEXITCODE }
        return 0
    }
    function ask($question, $default) { # takes the default under a plan or without a console
        if ($NONINTERACTIVE) { say "$question -> $default (default, non-interactive)"; return $default }
        $reply = Read-Host "$question [$default]"
        if ([string]::IsNullOrWhiteSpace($reply)) { return $default }
        return $reply.Trim()
    }
    function confirm($question, $default) { return ((ask "$question (y/n)" $default) -match '^[Yy]') }

    function wingetInstall([string[]]$ids, [string]$label) { # each id once per run; a failed id never stops the rest
        $bad = @()
        $todo = @($ids | Where-Object { $_ -and -not $DONE.ContainsKey($_) })
        if ($todo.Count -eq 0) { return }
        say "Installing $label ($($todo.Count) packages)"
        foreach ($id in $todo) {
            $DONE[$id] = 1
            $rc = run "winget install --id $id $($WINGET_FLAGS -join ' ')" { winget install --id $id @WINGET_FLAGS }
            if ($WINGET_REBOOT -contains $rc) { $STATE.NeedReboot = $true }
            elseif ($WINGET_OK -notcontains $rc) { $bad += "$id ($(hex $rc))" }
        }
        if ($bad.Count) { warn "Failed: $($bad -join ', ')"; record fail "${label}: $($bad -join ', ')" }
        else { record ok $label }
    }
    function setRegistry($path, $name, $value, $type = 'DWord') { # returns "same|name", "changed|name" or "failed|name"
        $now = $null
        try { $now = (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { }
        if ($null -ne $now -and (@($now) -join ',') -eq (@($value) -join ',')) { return "same|$name" }
        $rc = run "set $path\$name = $(@($value) -join ',') ($type)" {
            if (-not (Test-Path $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }   # on a fresh install the key itself can be missing
            New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force -ErrorAction Stop | Out-Null
        }
        if ($rc) { warn "Could not write $name under $path (Windows may protect it on this build)."; return "failed|$name" }
        return "changed|$name"
    }

    # ==== 3. checkSystem ====
    function isElevated {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    function interactiveUserSid { # the desktop belongs to whoever owns explorer.exe in this session, not always who accepted UAC
        $session = (Get-Process -Id $PID).SessionId
        $explorer = Get-CimInstance Win32_Process -Filter "name='explorer.exe' AND SessionId=$session" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $explorer) { return $null }
        try { return (Invoke-CimMethod -InputObject $explorer -MethodName GetOwnerSid -ErrorAction Stop).Sid } catch { return $null }
    }
    function guarded([scriptblock]$query, $fallback) { try { $v = & $query; if ($null -eq $v -or "$v" -eq '') { return $fallback }; return $v } catch { return $fallback } }
    function gpuVendors {
        $found = @()
        foreach ($g in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
            if ($g.PNPDeviceID -match 'VEN_10DE') { $found += 'nvidia' }
            elseif ($g.PNPDeviceID -match 'VEN_1002') { $found += 'amd' }
            elseif ($g.PNPDeviceID -match 'VEN_8086') { $found += 'intel' }
        }
        return (@($found | Select-Object -Unique) -join ' ')
    }
    function virtOf($maker, $model) {
        if ($model -match 'VirtualBox' -or $maker -match 'innotek') { return 'virtualbox' }
        if ($maker -match 'VMware') { return 'vmware' }
        if ($maker -match 'Microsoft' -and $model -match 'Virtual') { return 'hyperv' }
        if ($maker -match 'QEMU|Red Hat' -or $model -match 'KVM|QEMU|Standard PC') { return 'kvm' }
        if ($maker -match 'Xen' -or $model -match 'HVM domU') { return 'xen' }
        if ($model -match 'Parallels') { return 'parallels' }
        return 'none'
    }
    function fakeFacts {
        $SYS.Edition = 'Windows (CARINO_SETUP_FAKE)'; $SYS.Build = [int](guarded { $env:CARINO_SETUP_BUILD } 26100)
        $SYS.Version = "10.0.$($SYS.Build)"; $SYS.Arch = guarded { $env:CARINO_SETUP_ARCH } 'AMD64'
        $SYS.Cpu = 'fake'; $SYS.Gpus = [string]$env:CARINO_SETUP_GPU; $SYS.Laptop = 'no'
        $SYS.Virt = guarded { $env:CARINO_SETUP_VIRT } 'none'; $SYS.SecureBoot = 'unknown'; $SYS.Tpm = 'unknown'
        $SYS.BitLocker = 'unknown'; $SYS.Disk = 'unknown'; $SYS.Winget = 'fake'; $SYS.Net = 'not checked'
        $SYS.Elevated = $true; $SYS.Server = $false; $SYS.Release = ''
    }
    function realFacts {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $SYS.Edition = $os.Caption; $SYS.Version = $os.Version; $SYS.Build = [int]$os.BuildNumber   # [int]: 9600 must not sort above 22000
        $SYS.Release = guarded { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).DisplayVersion } ''
        $SYS.Server = $os.ProductType -ne 1
        $SYS.Arch = guarded { $env:PROCESSOR_ARCHITEW6432 } $env:PROCESSOR_ARCHITECTURE   # a 32-bit shell on 64-bit Windows reports x86
        $SYS.Cpu = guarded { (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim() } 'unknown'
        $SYS.Gpus = gpuVendors
        $SYS.Laptop = if (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }
        $SYS.Virt = virtOf $cs.Manufacturer $cs.Model
        $SYS.SecureBoot = guarded { if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'on' } else { 'off' } } 'unsupported (legacy BIOS) or unknown'
        $SYS.Tpm = guarded { $t = Get-Tpm -ErrorAction Stop; if ($t.TpmPresent) { "present, ready: $($t.TpmReady)" } else { 'none' } } 'unknown'
        $SYS.BitLocker = guarded { [string](Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop).ProtectionStatus } 'unknown (no BitLocker cmdlets)'
        $SYS.Disk = guarded { '{0:N0} GiB free' -f ((Get-PSDrive C -ErrorAction Stop).Free / 1GB) } 'unknown'
        $SYS.Winget = guarded { if (Get-Command winget -ErrorAction Stop) { (winget --version) -join '' } } ''
        $SYS.Net = guarded { Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec 8 'https://cdn.winget.microsoft.com/cache/source.msix' -ErrorAction Stop | Out-Null; 'yes' } 'no'
        $SYS.Elevated = isElevated
    }
    function printFacts {
        banner 'System'
        $rows = [ordered]@{
            'Windows' = "$($SYS.Edition) $($SYS.Release)".Trim(); 'Version' = "$($SYS.Version) (build $($SYS.Build))"
            'Architecture' = $SYS.Arch; 'CPU' = $SYS.Cpu; 'GPU' = $(if ($SYS.Gpus) { $SYS.Gpus } else { 'none found' })
            'Laptop' = $SYS.Laptop; 'Virtual machine' = $SYS.Virt; 'Secure Boot' = $SYS.SecureBoot; 'TPM' = $SYS.Tpm
            'BitLocker C:' = $SYS.BitLocker; 'Disk C:' = $SYS.Disk; 'winget' = $(if ($SYS.Winget) { $SYS.Winget } else { 'not found' })
            'Internet' = $SYS.Net; 'Administrator' = $SYS.Elevated
        }
        foreach ($k in $rows.Keys) { Write-Host ('  {0,-17} {1}' -f $k, $rows[$k]) }
    }
    function checkSystem {
        if ($FAKE) { fakeFacts } else { realFacts }
        printFacts
        if ($SYS.Build -lt 10240) { refuse "Build $($SYS.Build) is older than Windows 10 (10240) and is not supported." }
        if (-not $SYS.Elevated) {
            if ($DRYRUN) { warn 'Not elevated: a real run needs an administrator PowerShell.' }
            else { refuse 'This script needs administrator rights.' 'Open PowerShell with "Run as administrator" and run it again.' }
        }
        if (-not $SYS.Winget) {
            if ($DRYRUN) { warn 'winget was not found; the dry run prints its commands anyway.' }
            else { refuse 'winget was not found.' 'Install or update "App Installer" from the Microsoft Store (https://apps.microsoft.com/detail/9NBLGGH4NNS1), then run this again.' }
        }
        if ($SYS.Net -eq 'no') { warn 'The winget source did not answer: installs will fail until the internet works.' }
        if ($SYS.Server) { warn 'Windows Server: the profiles are desktop apps and some will not install here.' }
        if ($FAKE) { return }
        $shellSid = interactiveUserSid
        if ($shellSid -and $shellSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
            warn 'You elevated with a different account than the one logged in at the desktop.'
            warn 'HKCU tweaks and per-user winget installs would land in the elevating account, not on this desktop.'
            if (-not (confirm 'Continue anyway?' 'n')) { refuse 'Stopped: run it from an administrator shell of the desktop account.' }
        }
    }

    # ==== 4. Packages ====
    # winget ids (tools/check-winget.sh checks each against winget-pkgs). A purpose installs the groups listed
    # for it in $PURPOSES; every purpose has a list of its own named like the purpose.
    $PKG = @{
        'base'                = @('7zip.7zip', 'Mozilla.Firefox', 'SumatraPDF.SumatraPDF', 'CodecGuide.K-LiteCodecPack.Basic', 'Microsoft.DotNet.DesktopRuntime.8', 'Microsoft.DotNet.DesktopRuntime.10', 'EclipseAdoptium.Temurin.21.JRE', 'Git.Git', 'Notepad++.Notepad++', 'Microsoft.PowerShell', 'Microsoft.Sysinternals.Suite', 'MediaArea.MediaInfo.GUI')
        'vcredist_AMD64'      = @('Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86')
        'vcredist_ARM64'      = @('Microsoft.VCRedist.2015+.arm64', 'Microsoft.VCRedist.2015+.x64')
        'vcredist_x86'        = @('Microsoft.VCRedist.2015+.x86')
        'drivers_intel'       = @('Intel.IntelDriverAndSupportAssistant')
        'guest_kvm'           = @('RedHat.VirtIO')
        'google'              = @('Google.Chrome')
        'microsoft'           = @('Microsoft.VisualStudioCode', 'Microsoft.Teams')
        'support'             = @('KeePassXCTeam.KeePassXC', 'MHNexus.HxD', 'mRemoteNG.mRemoteNG')
        'remote'              = @('AnyDesk.AnyDesk')
        'basic'               = @('TheDocumentFoundation.LibreOffice', 'Mozilla.Thunderbird', 'VideoLAN.VLC', 'OBSProject.OBSStudio', 'Transmission.Transmission', 'yt-dlp.yt-dlp', 'Gyan.FFmpeg', 'AdrienAllard.FileConverter', 'WinDirStat.WinDirStat')
        'gaming'              = @('Valve.Steam', 'HeroicGamesLauncher.HeroicGamesLauncher', 'Discord.Discord', 'Guru3D.Afterburner')
        'corporate'           = @('ONLYOFFICE.DesktopEditors', 'Cisco.Webex', 'Zoom.Zoom', 'WireGuard.WireGuard', 'OpenVPNTechnologies.OpenVPN')
        'corporate-microsoft' = @('Microsoft.Office', 'Microsoft.PowerToys')
        'corporate-google'    = @('Google.GoogleDrive')
        'development'         = @('Python.Python.3.13', 'OpenJS.NodeJS.LTS', 'GoLang.Go', 'Rustlang.Rustup', 'Kitware.CMake', 'RedHat.Podman', 'RedHat.Podman-Desktop', 'VSCodium.VSCodium', 'Microsoft.WindowsTerminal')
        'astronomy'           = @('Stellarium.Stellarium', 'Free-Astro.Siril', 'KDE.KStars')
        'compneuro'           = @('Python.Python.3.13', 'Anaconda.Miniconda3', 'Spyder.Spyder')
        'design'              = @('GIMP.GIMP.3', 'Inkscape.Inkscape', 'KDE.Krita', 'BlenderFoundation.Blender', 'Scribus.Scribus', 'darktable.darktable', 'KDE.Kdenlive', 'ImageMagick.ImageMagick', 'FontForge.FontForge')
        'music'               = @('Audacity.Audacity', 'LMMS.LMMS', 'Hydrogen-Music.Hydrogen', 'Mixxx.Mixxx', 'Musescore.Musescore')
        'cybersecurity'       = @('Insecure.Nmap', 'WiresharkFoundation.Wireshark', 'ZAP.ZAP')
        'forensics'           = @('SleuthKit.Autopsy', 'OliverBetz.ExifTool', 'CGSecurity.TestDisk')
        'scientific'          = @('GNU.Octave', 'gnuplot.gnuplot', 'RProject.R', 'Python.Python.3.13', 'Spyder.Spyder', 'Scilab.Scilab', 'Kitware.ParaView', 'MiKTeX.MiKTeX')
        'robotics'            = @('ArduinoSA.IDE.stable', 'FreeCAD.FreeCAD', 'OpenSCAD.OpenSCAD', 'KiCad.KiCad', 'PuTTY.PuTTY')
        'imagenology'         = @('WeasisTeam.Weasis', 'Kitware.Slicer', 'MicroDicom.DICOMViewer')
    }
    # "name|menu label|groups": the menu number is the position (1-15), the same names as setup.sh
    $PURPOSES = @(
        'basic|Basic|basic google microsoft support remote'
        'gaming|Gaming|basic gaming google microsoft support remote'
        'corporate|Corporate|basic corporate google microsoft support remote'
        'corporate-microsoft|Corporate (Microsoft only)|basic corporate corporate-microsoft microsoft support remote'
        'corporate-google|Corporate (Google only)|basic corporate corporate-google google support remote'
        'development|Development|basic development google support remote'
        'astronomy|Astronomy|basic astronomy google support remote'
        'compneuro|Computational Neuroscience|basic compneuro support remote'
        'design|Design|basic design support remote'
        'music|Music Production|basic music support remote'
        'cybersecurity|Cybersecurity|basic cybersecurity support remote'
        'forensics|Forensics|basic forensics support remote'
        'scientific|Scientific|basic scientific support remote'
        'robotics|Robotics|basic robotics development support remote'
        'imagenology|Medical Imaging (Imagenologia)|basic imagenology support remote'
    )

    # ==== 5. baseSetup ====
    function baseSetup {
        banner 'Base setup'
        $rc = run 'winget source update' { winget source update }
        if ($rc) { record fail 'winget source update' } else { record ok 'winget source update' }
        wingetInstall $PKG['base'] 'base apps'
        if ($PKG.ContainsKey("vcredist_$($SYS.Arch)")) { wingetInstall $PKG["vcredist_$($SYS.Arch)"] 'Visual C++ runtimes' }
        else { say "No Visual C++ runtime list for $($SYS.Arch)." }
        driversSetup
    }

    # ==== 6. driversSetup ====
    function driversSetup {
        banner 'Drivers'
        foreach ($v in ($SYS.Gpus -split ' ' | Where-Object { $_ })) {
            switch ($v) {
                'nvidia' {
                    say 'NVIDIA: the NVIDIA App is not in winget. Windows Update installs a WHQL driver; for the newest one:'
                    say '  https://www.nvidia.com/en-us/software/nvidia-app/'; record skip 'NVIDIA app (download link printed)'
                }
                'amd' {
                    say 'AMD: Adrenalin is not in winget. Windows Update installs a WHQL driver; for the newest one:'
                    say '  https://www.amd.com/en/support/download/drivers.html'; record skip 'AMD Adrenalin (download link printed)'
                }
                'intel' { if (confirm 'Install Intel Driver & Support Assistant?' 'y') { wingetInstall $PKG['drivers_intel'] 'Intel driver assistant' } else { record skip 'Intel driver assistant' } }
            }
        }
        if (-not $SYS.Gpus) { say 'No NVIDIA, AMD or Intel GPU found; Windows Update provides the display driver.' }
        switch ($SYS.Virt) {
            'none'       { }
            'kvm'        { if (confirm 'Install the VirtIO guest tools (QEMU/KVM)?' 'y') { wingetInstall $PKG['guest_kvm'] 'VirtIO guest tools' } }
            'hyperv'     { say 'Hyper-V: the integration services are built into Windows.' }
            'vmware'     { say 'VMware: install VMware Tools from the VM menu (VM > Install VMware Tools); it is not in winget.' }
            'virtualbox' { say 'VirtualBox: Devices > Insert Guest Additions CD image, then run VBoxWindowsAdditions.exe.' }
            default      { say "Virtual machine ($($SYS.Virt)): install its guest tools from the hypervisor." }
        }
    }

    # ==== 7. Tweaks ====
    $EXPLORER_ADV = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    function tweaksSetup {
        banner "Tweaks (Windows $(if ($SYS.Build -ge 22000) { '11' } else { '10' }))"
        $writes = @(
            setRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' 0   # dark apps
            setRegistry $EXPLORER_ADV 'HideFileExt' 0                                                                 # show file extensions
            setRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'SearchBoxTaskbarMode' 0             # no taskbar search box
        )
        if ($SYS.Build -ge 22000) {
            $writes += setRegistry $EXPLORER_ADV 'ShowTaskViewButton' 0
            $writes += setRegistry $EXPLORER_ADV 'TaskbarDa' 0   # Widgets
            $writes += setRegistry $EXPLORER_ADV 'TaskbarMn' 0   # Chat (older 11 builds)
        } else {
            $writes += setRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds' 'ShellFeedsTaskbarViewMode' 2   # News and interests off
            $writes += setRegistry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'link' ([byte[]](0, 0, 0, 0)) 'Binary'   # no "- Shortcut" suffix
        }
        $n = @($writes | Where-Object { $_ -like 'changed|*' }).Count
        $failed = @($writes | Where-Object { $_ -like 'failed|*' } | ForEach-Object { ($_ -split '\|')[1] })
        if ($n) {
            $session = (Get-Process -Id $PID).SessionId   # only this desktop's Explorer, not other signed-in users'
            run "Stop-Process explorer in session $session   (Explorer restarts and reloads the settings)" { Get-Process explorer -ErrorAction Stop | Where-Object SessionId -eq $session | Stop-Process -Force -ErrorAction Stop } | Out-Null
        }
        if ($failed.Count) { record fail "tweaks ($n changed, could not write: $($failed -join ', '))" }
        elseif ($n -eq 0) { say 'Every tweak was already in place.'; record ok 'tweaks (already set)' }
        else { record ok "tweaks ($n changed)" }
    }

    # ==== 8. Profiles ====
    function purposeEntry($name) { return ($PURPOSES | Where-Object { ($_ -split '\|')[0] -eq $name } | Select-Object -First 1) }
    function installPurpose($name) {
        $entry = purposeEntry $name
        if (-not $entry) { fail "Unknown purpose '$name'."; return }
        $name, $label, $groups = $entry -split '\|'
        banner "Purpose: $name ($label)"
        if ($name -eq 'cybersecurity') { warn 'Dual-use tools: use them only where you are allowed to. Nmap and Wireshark may ask for Npcap separately.' }
        if ($name -eq 'compneuro') {
            say 'Brian 2: conda install -c conda-forge brian2 (after Miniconda). conda-forge has no Windows build of NEST or NEURON:'
            say '  NEST runs in WSL (offered under development); NEURON has a Windows installer at https://www.neuron.yale.edu'
        }
        foreach ($g in ($groups -split ' ')) {
            if ($PKG.ContainsKey($g) -and $PKG[$g].Count) { wingetInstall $PKG[$g] "$g apps" }
            else { say "Nothing in '$g' for Windows." }
        }
        if ($name -eq 'development' -and (confirm 'Install WSL with Ubuntu (needs a restart)?' 'n')) { wslSetup }
    }
    function profileMenu {
        banner 'Purpose profiles'
        for ($i = 0; $i -lt $PURPOSES.Count; $i++) { Write-Host ('  {0,2}) {1}' -f ($i + 1), ($PURPOSES[$i] -split '\|')[1]) }
        $reply = ask "Profile numbers, several allowed, e.g. '2 6' (0 = none)" '1'
        foreach ($n in ($reply -split '[\s,]+' | Where-Object { $_ })) {
            if ($n -eq '0') { return }
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $PURPOSES.Count) { installPurpose ($PURPOSES[[int]$n - 1] -split '\|')[0] }
            else { warn "'$n' is not a profile number, skipped." }
        }
    }

    # ==== 9. Extras ====
    function wslSetup {
        banner 'WSL'
        $rc = run 'wsl --install -d Ubuntu --no-launch' { wsl --install -d Ubuntu --no-launch }
        if ($rc) { record fail "WSL ($(hex $rc))" } else { record ok 'WSL with Ubuntu (open Ubuntu from Start after the restart)'; $STATE.NeedReboot = $true }
    }

    # ==== 10. Windows Update ====
    function updateSetup {
        banner 'Windows Update'
        $rc = run 'winget upgrade --all' { winget upgrade --all --silent --accept-source-agreements --accept-package-agreements --disable-interactivity }
        if ($WINGET_OK -contains $rc) { record ok 'winget upgrade --all' } else { record fail "winget upgrade --all ($(hex $rc))" }
        # PSWindowsUpdate loads a .psm1 and a .ps1xml, which the default Restricted policy refuses under "iwr | iex"
        $rc = run 'Set-ExecutionPolicy Bypass -Scope Process (this window only, nothing is saved); Install-PackageProvider NuGet; Install-Module PSWindowsUpdate' {
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null   # PSGallery prompts for NuGet otherwise
            Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -ErrorAction Stop   # -Force also silences the untrusted repository question
            Import-Module PSWindowsUpdate -Force -ErrorAction Stop
        }
        if ($rc) { record fail 'PSWindowsUpdate module'; return }
        # -IgnoreReboot: the restart is the user's decision at the end, not the module's
        $rc = run 'Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot' { Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -ErrorAction Stop }
        if ($rc) { record fail 'Windows Update' } else { record ok 'Windows Update'; $STATE.NeedReboot = $true }
    }

    # ==== 11. Plan ====
    function planParse { # validates every token before anything runs; one bad token refuses the plan
        $bad = $false; $action = $false
        $valid = @($PURPOSES | ForEach-Object { ($_ -split '\|')[0] })
        foreach ($t in ($PLAN -split '[,\r\n]+')) {
            $t = $t.Trim()
            if (-not $t) { continue }
            if ($t -in @('technical', 'drivers', 'tweaks', 'update', 'wsl')) { $action = $true }
            elseif ($t -like 'purpose=*') {
                if ($valid -contains $t.Substring(8)) { $action = $true } else { fail "Unknown purpose in '$t'. Valid purposes: $($valid -join ' ')"; $bad = $true }
            }
            elseif ($t -in @('reboot=yes', 'reboot=no')) { }
            elseif ($t -like 'reboot=*') { fail "reboot takes yes or no, not '$($t.Substring(7))'."; $bad = $true }
            else { fail "Unknown plan token '$t'. Valid tokens: technical drivers tweaks update wsl purpose=<name> reboot=yes|no"; $bad = $true }
            $STATE.Tokens += $t
        }
        if (-not ($action -or $bad)) { fail 'The plan has nothing to do.'; $bad = $true }
        if ($bad) { fail 'The plan was refused; nothing was run.'; $STATE.ExitCode = 2; throw 'carino-refused' }
        say "Plan accepted: $($STATE.Tokens -join ' ')"
    }
    function planRun {
        foreach ($t in $STATE.Tokens) {
            say "Plan step: $t"
            switch -Wildcard ($t) {
                'technical' { baseSetup }
                'drivers'   { driversSetup }
                'tweaks'    { tweaksSetup }
                'update'    { updateSetup }
                'wsl'       { wslSetup }
                'purpose=*' { installPurpose $t.Substring(8) }
                'reboot=*'  { $STATE.Reboot = $t.Substring(7) }
            }
        }
        say 'CARINO_SETUP_PLAN has finished.'
    }

    # ==== 12. Main ====
    function logFolder { # the current folder, unless it is System32 (where an elevated shell starts) or not a folder at all
        $here = Get-Location
        if ($here.Provider.Name -eq 'FileSystem' -and -not ($env:windir -and $here.Path -like "$env:windir*")) { return $here.Path }
        return [Environment]::GetFolderPath('UserProfile')
    }
    function openLog {
        if ($DRYRUN -and -not $env:CARINO_SETUP_LOG) { return }
        $STATE.Log = if ($env:CARINO_SETUP_LOG) { $env:CARINO_SETUP_LOG } else { Join-Path (logFolder) ("carino-setup-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
        try { Start-Transcript -Path $STATE.Log -Append -ErrorAction Stop | Out-Null } catch { warn "Could not log to $($STATE.Log): $_"; $STATE.Log = '' }
    }
    function interactive {
        if (confirm 'Run the base setup (base apps, runtimes, drivers)?' 'y') { baseSetup } else { record skip 'base setup' }
        if (confirm 'Apply the Explorer tweaks (dark apps, file extensions, cleaner taskbar)?' 'y') { tweaksSetup } else { record skip 'tweaks' }
        profileMenu
        if (confirm 'Run Windows Update and upgrade every winget app?' 'y') { updateSetup } else { record skip 'Windows Update' }
    }
    function finish {
        banner 'Summary'
        foreach ($r in $RESULTS) { $s, $w = $r -split '\|', 2; Write-Host ('  {0,-5} {1}' -f $s, $w) }
        if ($RESULTS.Count -eq 0) { say 'Nothing was installed.' }
        if ($STATE.Log) { say "Log: $($STATE.Log)" }
        if ($DRYRUN) { say 'Dry run: nothing was changed.' }
        if ($STATE.NeedReboot) { warn 'A restart is needed to finish some installs or updates.' }
        $yes = switch ($STATE.Reboot) { 'yes' { $true } 'no' { say 'Reboot: no (plan).'; $false } default { confirm 'Restart now?' 'n' } }
        if ($yes) { run 'Restart-Computer -Force' { Restart-Computer -Force } | Out-Null }
    }
    function main {
        Write-Host 'Carino SimpleSetup - Microsoft Windows' -ForegroundColor Cyan
        if ($PLAN) { planParse }
        openLog
        if ($DRYRUN) { say 'Dry run: every system-changing command is printed and nothing is run.' }
        checkSystem
        if ($PLAN) { planRun } else { interactive }
        finish
    }

    try { main }
    catch {
        if ("$_" -ne 'carino-refused') { fail "Unexpected error: $_" }
        if ($STATE.ExitCode -eq 0) { $STATE.ExitCode = 1 }
    }
    finally { if ($STATE.Log) { try { Stop-Transcript | Out-Null } catch { } } }
    if ($CarinoSetup.File) { exit $STATE.ExitCode }   # only when run as a file: under "iwr | iex" exit would close the user's window
}
& $CarinoSetup
