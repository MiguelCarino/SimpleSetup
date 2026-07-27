# Carino Setup test harness for the Windows half. Run from the repository root: .\test.ps1
# Checks only, it never installs anything and never writes to the registry.
$script:pass = 0
$script:fail = 0
function ok($m)    { $script:pass++; Write-Host "  pass  $m" -ForegroundColor Green }
function bad($m)   { $script:fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
function note($m)  { Write-Host "  note  $m" -ForegroundColor Yellow }
function section($m){ Write-Host ""; Write-Host $m -ForegroundColor Cyan }

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$target = Join-Path $root "setup.ps1"
if (-not (Test-Path $target)) { Write-Host "setup.ps1 not found next to this script." -ForegroundColor Red; exit 1 }

section "1. Parse"
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errors)
if ($errors.Count -eq 0) { ok "setup.ps1 parses with no syntax errors" }
else { foreach ($e in $errors) { bad ("line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) } }

section "2. No batch syntax left in a PowerShell file"
$lines = Get-Content $target
$batch = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*REM\s' -or $lines[$i] -match '^\s*REG\s+ADD\s' -or $lines[$i] -match '%1\\') { $batch += ("line {0}: {1}" -f ($i + 1), $lines[$i].Trim()) }   # REM, REG ADD and %1 are cmd constructs that parse as commands here and then fail at runtime
}
if ($batch.Count -eq 0) { ok "no REM, REG ADD or %1 constructs" } else { foreach ($b in $batch) { bad $b } }

section "3. Every command the script calls actually resolves"
$defined = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name }
$called  = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique
$external = @("winget", "Install-WindowsUpdate")   # winget ships with the App Installer package and Install-WindowsUpdate comes from PSWindowsUpdate, which this script installs itself
foreach ($c in $called) {
    if ($defined -contains $c) { ok "$c is defined in this script" }
    elseif (Get-Command $c -ErrorAction SilentlyContinue) { ok "$c resolves" }
    elseif ($external -contains $c) { note "$c is expected to be absent until the script installs or the OS provides it" }
    else { bad "$c does not resolve and is not defined in the script" }
}

section "4. Profile menu numbering matches the switch that dispatches it"
$promptLine = $lines | Where-Object { $_ -match 'Read-Host -Prompt "Now you must choose' } | Select-Object -First 1
if (-not $promptLine) { bad "could not find the profile menu prompt" }
else {
    $printed = ([regex]::Matches($promptLine, '`n(\d+)\.') | ForEach-Object { [int]$_.Groups[1].Value }) | Sort-Object
    $body = ($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'installPackages' }, $true) | Select-Object -First 1)
    $dispatched = ([regex]::Matches($body.Extent.Text, '"(\d+)"\s*\{') | ForEach-Object { [int]$_.Groups[1].Value }) | Sort-Object
    if (($printed -join ',') -eq ($dispatched -join ',')) { ok ("menu prints [{0}] and the switch dispatches the same" -f ($printed -join ' ')) }
    else { bad ("menu prints [{0}] but the switch dispatches [{1}]" -f ($printed -join ' '), ($dispatched -join ' ')) }
}

section "5. Windows version gate"
$gate = ($lines | Where-Object { $_ -match '\$windowsBuild\s*=' } | Select-Object -First 1)
if ($gate -match '\[int\]') { ok "the build number is compared as a number, not a string" } else { bad "the build number is not cast to [int], so 9600 would sort above 22000" }
foreach ($b in 10240, 19045, 22000, 22631, 26100, 29999) {
    $win11 = $b -ge 22000
    $win10 = $b -ge 10240
    if ($win11 -or $win10) { ok ("build {0} reaches the {1} path" -f $b, $(if ($win11) { "Windows 11" } else { "Windows 10" })) }
    else { bad ("build {0} reaches no path at all" -f $b) }
}
if ($lines -match 'Default\s*\{\s*error') { ok "an unsupported build is reported rather than silently ignored" } else { bad "no Default arm reports an unsupported build" }

section "6. Honesty of the FOSS profile"
$fossBlock = ""
$inFoss = $false
foreach ($l in $lines) {
    if ($l -match '^\s*"4"\s*\{') { $inFoss = $true; continue }
    if ($inFoss -and $l -match '^\s*"5"\s*\{') { break }
    if ($inFoss) { $fossBlock += ($l -replace '#.*$', '') + "`n" }   # trailing comments are stripped first, the line that replaced VS Code names it in its own explanation and would otherwise read as a proprietary install
}
$proprietary = @("Microsoft.VisualStudioCode", "Spotify.Spotify", "Google.Chrome", "Oracle.JavaRuntimeEnvironment", "CodecGuide.K-LiteCodecPack", "AnyDeskSoftwareGmbH.AnyDesk", "Valve.Steam")
$found = $proprietary | Where-Object { $fossBlock -match [regex]::Escape($_) -and $fossBlock -notmatch ('#\s*"' + [regex]::Escape($_)) }
if (-not $found) { ok "the FOSS profile installs nothing proprietary" } else { bad ("the FOSS profile claims 'ONLY open source' but installs: {0}" -f ($found -join ', ')) }

section "7. Unattended installs cannot hang"
$installs = $lines | Where-Object { $_ -match 'winget install' }
$bare = $installs | Where-Object { $_ -notmatch '@wingetFlags' }
if ($installs.Count -eq 0) { bad "no winget install calls found at all" }
elseif ($bare.Count -eq 0) { ok ("all {0} winget calls pass the unattended flag set" -f $installs.Count) }
else { bad ("{0} winget call(s) run without the unattended flags and can block on a prompt" -f $bare.Count) }

Write-Host ""
Write-Host "-------------------------------------" -ForegroundColor Cyan
if ($script:fail -eq 0) { Write-Host "$script:pass passed, 0 failed." -ForegroundColor Green; exit 0 }
else { Write-Host "$script:pass passed, $script:fail FAILED." -ForegroundColor Red; exit 1 }
