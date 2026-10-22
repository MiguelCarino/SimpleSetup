# Carino SimpleSetup test harness for setup.ps1. Run from the repository root: ./test.ps1
# Works under PowerShell 7 (Windows, Linux, macOS) and Windows PowerShell 5.1. It never installs anything:
# every run of setup.ps1 here uses CARINO_SETUP_FAKE=1, which forces a dry run with made-up facts.
$script:pass = 0
$script:fail = 0
function ok($m)      { $script:pass++; Write-Host "  pass  $m" -ForegroundColor Green }
function bad($m)     { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
function note($m)    { Write-Host "  note  $m" -ForegroundColor Yellow }
function section($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan }
function check($cond, $good, $bad) { if ($cond) { ok $good } else { bad $bad } }

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$target = Join-Path $root 'setup.ps1'
$bashScript = Join-Path $root 'setup.sh'
if (-not (Test-Path $target)) { Write-Host 'setup.ps1 not found next to this script.' -ForegroundColor Red; exit 1 }

section '1. Parse'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errors)
if ($errors.Count -eq 0) { ok 'setup.ps1 parses with no syntax errors' }
else { foreach ($e in $errors) { bad ('line {0}: {1}' -f $e.Extent.StartLineNumber, $e.Message) } }

section '2. Windows PowerShell 5.1 compatibility'
$ps7 = @('QuestionMark', 'QuestionQuestion', 'QuestionQuestionEquals', 'AndAnd', 'OrOr', 'QuestionDot', 'QuestionLBracket', 'Clean')
$hits = @($tokens | Where-Object { $ps7 -contains $_.Kind.ToString() })
check ($hits.Count -eq 0) 'no ternary, ??, ?., && or || tokens' ("PowerShell 7 only syntax: " + (($hits | ForEach-Object { "line $($_.Extent.StartLineNumber) '$($_.Text)'" }) -join ', '))
$par = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandParameterAst] -and $n.ParameterName -in @('Parallel', 'AsJob', 'ThrottleLimit') }, $true))
check ($par.Count -eq 0) 'no -Parallel / -ThrottleLimit' ('7-only parameters at lines ' + (($par | ForEach-Object { $_.Extent.StartLineNumber }) -join ' '))
$bytes = [System.IO.File]::ReadAllBytes($target)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$high = @($bytes | Where-Object { $_ -gt 127 }).Count
check ($hasBom -or $high -eq 0) 'ASCII-only source (5.1 reads a BOM-less file as ANSI)' "$high non-ASCII bytes and no BOM"
$batch = @(Get-Content $target | Where-Object { $_ -match '^\s*(REM|REG\s+ADD)\s' -or $_ -match '%1\\' })
check ($batch.Count -eq 0) 'no REM, REG ADD or %1 batch constructs' ("batch syntax: " + ($batch -join ' | '))

section '3. Purposes and packages (data in section 4)'
function valueOf($name) { # the literal value assigned to $name, evaluated only when it is a plain literal
    $a = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq "`$$name" }, $true)
    if (-not $a) { return $null }
    try { return $a.Right.Expression.SafeGetValue() } catch { return $null }
}
$PKG = valueOf 'PKG'
$PURPOSES = @(valueOf 'PURPOSES')
if (-not $PKG) { bad '$PKG is missing or is not a plain literal hashtable' } else { ok "`$PKG holds $($PKG.Count) lists" }
$psNames = @($PURPOSES | ForEach-Object { ($_ -split '\|')[0] })
$shNames = @()
if (Test-Path $bashScript) {
    $inside = $false
    foreach ($l in Get-Content $bashScript) {
        if ($l -match '^PURPOSES=\(') { $inside = $true; continue }
        if ($inside -and $l -match '^\)') { break }
        if ($inside -and $l -match '^\s*"([a-z0-9-]+)\|') { $shNames += $Matches[1] }
    }
}
if ($shNames.Count -eq 0) { bad 'could not read the PURPOSES list from setup.sh' }
else { check (($psNames -join ' ') -eq ($shNames -join ' ')) "the 15 purposes match setup.sh in name and order ($($shNames.Count))" "setup.ps1 [$($psNames -join ' ')] vs setup.sh [$($shNames -join ' ')]" }
$idRx = '^[A-Za-z0-9][A-Za-z0-9+-]*(\.[A-Za-z0-9+_-]+)+$'
if ($PKG) {
    foreach ($k in $PKG.Keys) {
        $list = @($PKG[$k])
        $badIds = @($list | Where-Object { $_ -notmatch $idRx })
        $dups = @($list | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        if ($badIds.Count) { bad "$k has malformed ids: $($badIds -join ', ')" }
        if ($dups.Count) { bad "$k lists twice: $($dups -join ', ')" }
        if (-not $badIds.Count -and -not $dups.Count) { ok "$k : $($list.Count) well-formed, unique ids" }
    }
    foreach ($p in $PURPOSES) {
        $name, $label, $groups = $p -split '\|'
        $missing = @($groups -split ' ' | Where-Object { -not $PKG.ContainsKey($_) })
        check ($missing.Count -eq 0) "purpose $name uses only known groups" "purpose $name names unknown groups: $($missing -join ' ')"
        check ($PKG.ContainsKey($name) -and ($groups -split ' ') -contains $name) "purpose $name has its own list and installs it" "purpose $name has no list of its own, or does not install it"
    }
    $text = Get-Content $target -Raw
    $used = @($PURPOSES | ForEach-Object { ($_ -split '\|')[2] -split ' ' })
    foreach ($k in $PKG.Keys) {
        $refd = $used -contains $k -or $text -match ("PKG\['" + [regex]::Escape($k) + "'\]") -or ($k -like 'vcredist_*' -and $text -match 'vcredist_\$')
        if (-not $refd) { bad "the list '$k' is never installed" }
    }
    $wi = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'winget' -and $n.CommandElements.Count -gt 1 -and $n.CommandElements[1].Extent.Text -eq 'install' }, $true))
    $bare = @($wi | Where-Object { -not ($_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Splatted -and $_.VariablePath.UserPath -eq 'WINGET_FLAGS' }) })
    check ($wi.Count -gt 0 -and $bare.Count -eq 0) "every winget install ($($wi.Count)) splats @WINGET_FLAGS" ('winget install without @WINGET_FLAGS at lines ' + (($bare | ForEach-Object { $_.Extent.StartLineNumber }) -join ' '))
}

section '4. Every command the script calls is defined or known'
$defined = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$called = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
# Windows-only or installed by the script itself: absent on Linux pwsh, or until PSWindowsUpdate is installed
$known = @('winget', 'wsl', 'Install-WindowsUpdate', 'Confirm-SecureBootUEFI', 'Get-Tpm', 'Get-BitLockerVolume', 'Get-CimInstance', 'Invoke-CimMethod',
    'Install-PackageProvider', 'Install-Module', 'Import-Module', 'Restart-Computer', 'Stop-Process', 'Get-PSDrive', 'New-ItemProperty', 'Get-ItemProperty')
$unknown = @()
foreach ($c in $called) {
    if ($defined -contains $c -or $known -contains $c -or (Get-Command $c -ErrorAction SilentlyContinue)) { continue }
    $unknown += $c
}
check ($unknown.Count -eq 0) "all $($called.Count) called commands resolve ($($defined.Count) defined in the script)" ("unresolved: " + ($unknown -join ', '))
$unusedFns = @($defined | Where-Object { $called -notcontains $_ })
if ($unusedFns.Count) { note "defined but never called: $($unusedFns -join ', ')" }

section '5. Dry runs (CARINO_SETUP_FAKE=1)'
$exe = (Get-Process -Id $PID).Path
function dry($plan, $extra, [switch]$Iex) { # runs setup.ps1 in a child shell, returns @(exit code, output)
    $saved = @{}
    $vars = @{ CARINO_SETUP_FAKE = '1'; CARINO_SETUP_DRYRUN = '1'; CARINO_SETUP_PLAN = $plan; CARINO_SETUP_LOG = $null }
    if ($extra) { foreach ($k in $extra.Keys) { $vars[$k] = $extra[$k] } }
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    # -Iex is the README's "iwr | iex": piped into iex inside a function, under a caller's StrictMode, no Bypass
    $how = if ($Iex) { @('-Command', "Set-StrictMode -Version Latest; function go { Get-Content -LiteralPath '$target' -Raw | Invoke-Expression }; go") }
           else { @('-ExecutionPolicy', 'Bypass', '-File', $target) }
    $out = '' | & $exe -NoProfile -NonInteractive @how 2>&1 | Out-String
    $code = $LASTEXITCODE
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    return @($code, $out)
}
$r = dry 'technical,tweaks,purpose=gaming,purpose=development,wsl,update,reboot=no' @{ CARINO_SETUP_GPU = 'nvidia intel'; CARINO_SETUP_VIRT = 'kvm' }
check ($r[0] -eq 0) 'a full plan dry run exits 0' "a full plan dry run exited $($r[0])"
check ($r[1] -match 'Plan accepted' -and $r[1] -match 'CARINO_SETUP_PLAN has finished') 'the plan is accepted and finishes' 'the plan did not run to the end'
check ($r[1] -match '\(dry-run\) > winget install --id Valve\.Steam --exact') 'gaming installs Steam through winget (printed only)' 'Steam was not printed as a dry-run winget install'
check ($r[1] -match 'Intel\.IntelDriverAndSupportAssistant' -and $r[1] -match 'nvidia-app') 'GPU vendors: Intel via winget, NVIDIA link printed' 'driver handling for nvidia + intel is wrong'
check ($r[1] -match 'RedHat\.VirtIO') 'a KVM guest is offered the VirtIO tools' 'no VirtIO guest tools on KVM'
check ($r[1] -match 'wsl --install -d Ubuntu --no-launch') 'the wsl token prints the WSL install' 'the WSL install was not printed'
check ($r[1] -match 'Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot') 'Windows Update keeps -IgnoreReboot' 'Install-WindowsUpdate is missing or lost -IgnoreReboot'
check ($r[1] -match 'TaskbarDa' -and $r[1] -notmatch 'ShellFeedsTaskbarViewMode') 'build 26100 gets the Windows 11 tweaks only' 'the Windows 11 tweak set is wrong'
check ($r[1] -match 'Reboot: no \(plan\)' -and $r[1] -notmatch 'Restart-Computer') 'reboot=no does not restart' 'reboot=no was not honoured'
check ($r[1] -notmatch ' xx ') 'no failures reported' 'the dry run reported a failure (xx)'
$dupSteam = ([regex]::Matches($r[1], 'install --id Google\.Chrome ')).Count
check ($dupSteam -eq 1) 'an id shared by two purposes is installed once' "Google.Chrome was printed $dupSteam times"

$r = dry 'tweaks,reboot=no' @{ CARINO_SETUP_BUILD = '19045' }
check ($r[0] -eq 0 -and $r[1] -match 'ShellFeedsTaskbarViewMode' -and $r[1] -notmatch 'TaskbarDa') 'build 19045 gets the Windows 10 tweaks only' 'the Windows 10 tweak set is wrong'
$r = dry 'tweaks' @{ CARINO_SETUP_BUILD = '9600' }
check ($r[0] -ne 0 -and $r[1] -match 'older than Windows 10' -and $r[1] -notmatch 'Plan step') 'build 9600 is refused before anything runs' 'build 9600 was not refused'
$r = dry 'technical,purpose=nope,fly' $null
check ($r[0] -eq 2 -and $r[1] -match "Unknown purpose in 'purpose=nope'" -and $r[1] -match "Unknown plan token 'fly'" -and $r[1] -notmatch '==== System') 'unknown tokens refuse the whole plan with exit 2, before checkSystem' "a bad plan was not refused cleanly (exit $($r[0]))"
$r = dry 'reboot=maybe' $null
check ($r[0] -eq 2) 'reboot takes only yes or no' 'reboot=maybe was accepted'
$all = ($psNames | ForEach-Object { "purpose=$_" }) -join ','
$r = dry "$all,reboot=no" $null
check ($r[0] -eq 0 -and $r[1] -notmatch ' xx ') "all $($psNames.Count) purposes dry-run cleanly" "a purpose failed in the dry run (exit $($r[0]))"
$r = dry '' $null
check ($r[0] -eq 0 -and $r[1] -match 'default, non-interactive' -and $r[1] -match 'Purpose: basic' -and $r[1] -match 'Restart now\? \(y/n\) -> n') 'without a console the interactive flow takes the defaults (basic, no restart)' 'the non-interactive defaults are wrong'
$r = dry 'purpose=gaming,tweaks,update,reboot=no' $null -Iex
check ($r[1] -match 'Plan step: purpose=gaming' -and $r[1] -match 'install --id Valve\.Steam' -and $r[1] -match 'Reboot: no \(plan\)' -and $r[1] -notmatch 'Unexpected error|PropertyNotFound| xx ') 'under iwr | iex in a function with StrictMode the plan runs and keeps its state' 'the iex run lost its plan state or hit an error'
$r = dry 'purpose=nope' $null -Iex
check ($r[1] -match 'The plan was refused' -and $r[1] -notmatch 'Unexpected error|PropertyNotFound') 'under iwr | iex a bad plan is refused cleanly' 'the iex run of a bad plan hit an error'

Write-Host ''
Write-Host '-------------------------------------' -ForegroundColor Cyan
if ($script:fail -eq 0) { Write-Host "$script:pass passed, 0 failed." -ForegroundColor Green; exit 0 }
else { Write-Host "$script:pass passed, $script:fail FAILED." -ForegroundColor Red; exit 1 }
