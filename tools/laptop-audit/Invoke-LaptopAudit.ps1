<#
.SYNOPSIS
    Read-only health, performance and security audit of a Windows laptop.

.DESCRIPTION
    Collects system, hardware, battery, storage, software, startup, security,
    network, developer-toolchain and reliability data, scores it against a set
    of thresholds, and writes a Markdown + JSON report.

    The script NEVER changes anything: no writes outside the report directory,
    no registry edits, no service or setting changes. Everything degrades
    gracefully when run without administrator rights (some checks are simply
    reported as "needs admin").

.PARAMETER Deep
    Also scan the user profile for large files and duplicate files. Slow
    (minutes on a big profile), so it is opt-in.

.PARAMETER OutDir
    Where to write the report. Defaults to the Desktop, falling back to the
    user profile root.

.PARAMETER LargeFileMB
    Minimum size for a file to be listed in the -Deep large-file report.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Invoke-LaptopAudit.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Invoke-LaptopAudit.ps1 -Deep
#>
[CmdletBinding()]
param(
    [switch]$Deep,
    [string]$OutDir,
    [int]$LargeFileMB = 250
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Report   = [ordered]@{}
$script:Started  = Get-Date

# ---------------------------------------------------------------- helpers ---

function Safe {
    param([Parameter(Mandatory = $true)][scriptblock]$Block, $Default = $null)
    try {
        $r = & $Block 2>$null
        if ($null -eq $r) { return $Default }
        return $r
    } catch { return $Default }
}

function Add-Finding {
    param(
        [ValidateSet('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO')][string]$Severity,
        [string]$Area, [string]$Title, [string]$Detail, [string]$Fix
    )
    $script:Findings.Add([pscustomobject]@{
        Severity = $Severity; Area = $Area; Title = $Title; Detail = $Detail; Fix = $Fix
    })
}

function Section {
    param([string]$Name)
    Write-Host ''
    Write-Host "== $Name " -ForegroundColor Cyan -NoNewline
    Write-Host ('=' * [Math]::Max(3, 60 - $Name.Length)) -ForegroundColor DarkCyan
}

function Say { param([string]$Text) Write-Host "   $Text" }

function HumanBytes {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Get-FolderSize {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $m = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum
    [pscustomobject]@{
        Path  = $Path
        Bytes = [double]$m.Sum
        Files = [int]$m.Count
    }
}

$IsAdmin = Safe { ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator) } $false

Write-Host ''
Write-Host ' LAPTOP AUDIT ' -ForegroundColor Black -BackgroundColor Cyan
Write-Host " started $($script:Started.ToString('yyyy-MM-dd HH:mm')) | elevated: $IsAdmin | deep scan: $($Deep.IsPresent)"
Write-Host ' Read-only. Nothing on this machine is modified.' -ForegroundColor DarkGray

# ------------------------------------------------------------ 1. identity ---

Section 'System identity'

$os  = Safe { Get-CimInstance Win32_OperatingSystem }
$cs  = Safe { Get-CimInstance Win32_ComputerSystem }
$bios= Safe { Get-CimInstance Win32_BIOS }
$uptime = if ($os) { (Get-Date) - $os.LastBootUpTime } else { $null }

$script:Report['System'] = [ordered]@{
    Hostname       = $env:COMPUTERNAME
    User           = "$env:USERDOMAIN\$env:USERNAME"
    OS             = Safe { $os.Caption }
    Version        = Safe { $os.Version }
    Build          = Safe { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion }
    InstallDate    = Safe { $os.InstallDate.ToString('yyyy-MM-dd') }
    Manufacturer   = Safe { $cs.Manufacturer }
    Model          = Safe { $cs.Model }
    Serial         = Safe { $bios.SerialNumber }
    BiosVersion    = Safe { ($bios.SMBIOSBIOSVersion) }
    BiosDate       = Safe { $bios.ReleaseDate.ToString('yyyy-MM-dd') }
    LastBoot       = Safe { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm') }
    UptimeDays     = if ($uptime) { [Math]::Round($uptime.TotalDays, 1) } else { $null }
    PowerShell     = $PSVersionTable.PSVersion.ToString()
    Elevated       = $IsAdmin
}

Say "$($script:Report['System'].Manufacturer) $($script:Report['System'].Model)"
Say "$($script:Report['System'].OS) build $($script:Report['System'].Build) ($($script:Report['System'].Version))"
Say "Up for $($script:Report['System'].UptimeDays) days (last boot $($script:Report['System'].LastBoot))"

if ($uptime -and $uptime.TotalDays -gt 14) {
    Add-Finding -Severity 'LOW' -Area 'System' -Title 'Long uptime' `
        -Detail "Machine has been running $([Math]::Round($uptime.TotalDays,1)) days without a restart." `
        -Fix 'Restart to apply pending updates and clear leaked memory.'
}

$pendingReboot = @()
if (Safe { Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' } $false) { $pendingReboot += 'Component Based Servicing' }
if (Safe { Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' } $false) { $pendingReboot += 'Windows Update' }
if (Safe { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop) } $null) { $pendingReboot += 'Pending file renames' }
$script:Report['System']['PendingReboot'] = $pendingReboot
if ($pendingReboot.Count -gt 0) {
    Add-Finding -Severity 'MEDIUM' -Area 'System' -Title 'Reboot pending' `
        -Detail ("Reboot required by: " + ($pendingReboot -join ', ')) `
        -Fix 'Restart the machine to finish installing updates.'
    Say "Reboot pending: $($pendingReboot -join ', ')"
}

# ------------------------------------------------------------ 2. hardware ---

Section 'Hardware'

$cpu = Safe { Get-CimInstance Win32_Processor | Select-Object -First 1 }
$mem = Safe { Get-CimInstance Win32_PhysicalMemory }
$gpu = Safe { Get-CimInstance Win32_VideoController }

$totalRamB = Safe { [double]$cs.TotalPhysicalMemory } 0
$freeRamB  = Safe { [double]$os.FreePhysicalMemory * 1KB } 0
$ramUsedPct = if ($totalRamB -gt 0) { [Math]::Round((1 - ($freeRamB / $totalRamB)) * 100, 1) } else { $null }

$script:Report['Hardware'] = [ordered]@{
    CPU          = Safe { $cpu.Name }
    Cores        = Safe { $cpu.NumberOfCores }
    LogicalCores = Safe { $cpu.NumberOfLogicalProcessors }
    MaxClockMHz  = Safe { $cpu.MaxClockSpeed }
    RamTotal     = HumanBytes $totalRamB
    RamFree      = HumanBytes $freeRamB
    RamUsedPct   = $ramUsedPct
    RamModules   = Safe { @($mem | ForEach-Object {
                        "{0} {1} @ {2} MHz ({3})" -f $_.DeviceLocator, (HumanBytes ([double]$_.Capacity)), $_.Speed, $_.Manufacturer }) } @()
    MemorySlots  = Safe { (Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1).MemoryDevices }
    GPU          = Safe { @($gpu | ForEach-Object { "$($_.Name) (driver $($_.DriverVersion), $($_.DriverDate.ToString('yyyy-MM-dd')))" }) } @()
}

Say "$($script:Report['Hardware'].CPU)"
Say "$($script:Report['Hardware'].Cores) cores / $($script:Report['Hardware'].LogicalCores) threads"
Say "RAM $($script:Report['Hardware'].RamTotal) total, $($script:Report['Hardware'].RamFree) free ($ramUsedPct% in use)"
foreach ($g in $script:Report['Hardware'].GPU) { Say "GPU $g" }

if ($ramUsedPct -ne $null -and $ramUsedPct -ge 90) {
    Add-Finding -Severity 'HIGH' -Area 'Hardware' -Title 'Memory pressure' `
        -Detail "$ramUsedPct% of RAM is in use right now ($(HumanBytes $freeRamB) free of $(HumanBytes $totalRamB))." `
        -Fix 'Close heavy apps, or check the top-memory process list below for a leak.'
} elseif ($ramUsedPct -ne $null -and $ramUsedPct -ge 80) {
    Add-Finding -Severity 'MEDIUM' -Area 'Hardware' -Title 'High memory use' `
        -Detail "$ramUsedPct% of RAM in use." -Fix 'Worth watching; see top-memory processes.'
}
if ($totalRamB -gt 0 -and $totalRamB -lt 8GB) {
    Add-Finding -Severity 'MEDIUM' -Area 'Hardware' -Title 'Low installed RAM' `
        -Detail "Only $(HumanBytes $totalRamB) installed." `
        -Fix 'Under 8 GB is tight for a browser plus any dev tooling; consider an upgrade if slots are free.'
}

# Driver age
$oldDrivers = Safe { @($gpu | Where-Object { $_.DriverDate -and $_.DriverDate -lt (Get-Date).AddYears(-2) }) } @()
if ($oldDrivers.Count -gt 0) {
    Add-Finding -Severity 'LOW' -Area 'Hardware' -Title 'Stale GPU driver' `
        -Detail (($oldDrivers | ForEach-Object { "$($_.Name): driver dated $($_.DriverDate.ToString('yyyy-MM-dd'))" }) -join '; ') `
        -Fix 'Update from the GPU vendor (Intel/AMD/NVIDIA) rather than Windows Update.'
}

# ------------------------------------------------------------- 3. battery ---

Section 'Battery'

$batt = Safe { Get-CimInstance Win32_Battery | Select-Object -First 1 }
$design = Safe { (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity }
$full   = Safe { (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity }
$cycles = Safe { (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryCycleCount -ErrorAction Stop | Select-Object -First 1).CycleCount }

if (-not $batt) {
    Say 'No battery detected (desktop, or battery reporting unavailable).'
    $script:Report['Battery'] = @{ Present = $false }
} else {
    $healthPct = $null
    if ($design -and $full -and $design -gt 0) { $healthPct = [Math]::Round(($full / $design) * 100, 1) }
    $script:Report['Battery'] = [ordered]@{
        Present         = $true
        Name            = Safe { $batt.Name }
        ChargePct       = Safe { $batt.EstimatedChargeRemaining }
        Status          = Safe { $batt.BatteryStatus }
        DesignCapacity  = $design
        FullCapacity    = $full
        HealthPct       = $healthPct
        CycleCount      = $cycles
    }
    Say "Charge: $($script:Report['Battery'].ChargePct)%"
    if ($healthPct) {
        Say "Health: $healthPct% of design capacity ($full / $design mWh)"
        $wear = 100 - $healthPct
        if ($healthPct -lt 60) {
            Add-Finding -Severity 'HIGH' -Area 'Battery' -Title 'Battery badly degraded' `
                -Detail "Full-charge capacity is $healthPct% of design ($([Math]::Round($wear,1))% wear)." `
                -Fix 'Expect roughly half the original runtime. Replacement is the only real fix.'
        } elseif ($healthPct -lt 80) {
            Add-Finding -Severity 'MEDIUM' -Area 'Battery' -Title 'Battery wear' `
                -Detail "Full-charge capacity is $healthPct% of design ($([Math]::Round($wear,1))% wear)." `
                -Fix 'Normal for an older laptop. Enable a charge limit (80%) in vendor software if offered.'
        }
    } else {
        Say 'Capacity detail unavailable (firmware does not expose it).'
    }
    if ($cycles) { Say "Cycles: $cycles" }
}

# ------------------------------------------------------------- 4. storage ---

Section 'Storage'

$vols = Safe { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' } @()
$volInfo = @()
foreach ($v in $vols) {
    $pctFree = if ($v.Size -gt 0) { [Math]::Round(($v.FreeSpace / $v.Size) * 100, 1) } else { 0 }
    $volInfo += [pscustomobject]@{
        Drive     = $v.DeviceID
        Label     = $v.VolumeName
        Total     = HumanBytes ([double]$v.Size)
        Free      = HumanBytes ([double]$v.FreeSpace)
        PctFree   = $pctFree
    }
    Say "$($v.DeviceID) $(HumanBytes ([double]$v.FreeSpace)) free of $(HumanBytes ([double]$v.Size))  ($pctFree% free)"
    if ($pctFree -lt 5) {
        Add-Finding -Severity 'CRITICAL' -Area 'Storage' -Title "Drive $($v.DeviceID) nearly full" `
            -Detail "$pctFree% free ($(HumanBytes ([double]$v.FreeSpace)) of $(HumanBytes ([double]$v.Size)))." `
            -Fix 'Windows needs headroom for updates, paging and hibernation. Clear space now; see largest folders below.'
    } elseif ($pctFree -lt 15) {
        Add-Finding -Severity 'HIGH' -Area 'Storage' -Title "Drive $($v.DeviceID) low on space" `
            -Detail "$pctFree% free ($(HumanBytes ([double]$v.FreeSpace)) of $(HumanBytes ([double]$v.Size)))." `
            -Fix 'Run Storage Sense / Disk Cleanup and clear the largest folders listed below.'
    }
}

$phys = Safe { Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, @{n='SizeGB';e={[Math]::Round($_.Size/1GB,0)}} } @()
foreach ($d in $phys) {
    Say "$($d.FriendlyName) [$($d.MediaType), $($d.SizeGB) GB] health: $($d.HealthStatus)"
    if ($d.HealthStatus -and $d.HealthStatus -ne 'Healthy') {
        Add-Finding -Severity 'CRITICAL' -Area 'Storage' -Title 'Disk reporting unhealthy' `
            -Detail "$($d.FriendlyName) health status: $($d.HealthStatus) / $($d.OperationalStatus)." `
            -Fix 'Back up immediately and run the vendor diagnostic. A failing disk takes the whole archive with it.'
    }
}

$smart = Safe { Get-CimInstance -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop } @()
foreach ($s in $smart) {
    if ($s.PredictFailure) {
        Add-Finding -Severity 'CRITICAL' -Area 'Storage' -Title 'SMART predicts drive failure' `
            -Detail "$($s.InstanceName) reports PredictFailure = true (reason $($s.Reason))." `
            -Fix 'Back up now and replace the drive.'
    }
}

# Quick user-folder sizes
$quickPaths = @(
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Videos",
    "$env:USERPROFILE\Pictures",
    "$env:LOCALAPPDATA\Temp",
    "$env:WINDIR\Temp",
    "$env:LOCALAPPDATA\Packages",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
) | Where-Object { Test-Path -LiteralPath $_ }

$folderSizes = @()
foreach ($p in $quickPaths) {
    $fs = Get-FolderSize $p
    if ($fs) { $folderSizes += $fs }
}
$folderSizes = $folderSizes | Sort-Object Bytes -Descending
foreach ($f in $folderSizes) { Say ("{0,-10} {1}" -f (HumanBytes $f.Bytes), $f.Path) }

$tempBytes = ($folderSizes | Where-Object { $_.Path -like '*Temp*' -or $_.Path -like '*INetCache*' } |
              Measure-Object -Property Bytes -Sum).Sum
if ($tempBytes -gt 5GB) {
    Add-Finding -Severity 'MEDIUM' -Area 'Storage' -Title 'Large temp/cache footprint' `
        -Detail "Temp and cache folders total $(HumanBytes $tempBytes)." `
        -Fix 'Disk Cleanup (cleanmgr) or Settings > System > Storage > Temporary files.'
}
$dl = $folderSizes | Where-Object { $_.Path -like '*Downloads' } | Select-Object -First 1
if ($dl -and $dl.Bytes -gt 20GB) {
    Add-Finding -Severity 'LOW' -Area 'Storage' -Title 'Downloads folder is large' `
        -Detail "$(HumanBytes $dl.Bytes) across $($dl.Files) files." `
        -Fix 'Usually the cheapest space to reclaim.'
}

$recycle = Safe { (New-Object -ComObject Shell.Application).Namespace(0xA).Items() |
                  Measure-Object -Property Size -Sum } $null
if ($recycle -and $recycle.Sum -gt 0) {
    Say "Recycle Bin: $(HumanBytes ([double]$recycle.Sum)) in $($recycle.Count) items"
    if ($recycle.Sum -gt 5GB) {
        Add-Finding -Severity 'LOW' -Area 'Storage' -Title 'Recycle Bin holding space' `
            -Detail "$(HumanBytes ([double]$recycle.Sum)) recoverable." -Fix 'Empty the Recycle Bin.'
    }
}

$script:Report['Storage'] = [ordered]@{
    Volumes       = $volInfo
    PhysicalDisks = $phys
    FolderSizes   = $folderSizes | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Size = HumanBytes $_.Bytes; Bytes = $_.Bytes; Files = $_.Files } }
    RecycleBin    = if ($recycle) { HumanBytes ([double]$recycle.Sum) } else { 'n/a' }
}

# Shadow copies / hibernation / page file
$pagefile = Safe { Get-CimInstance Win32_PageFileUsage } @()
$script:Report['Storage']['PageFile'] = Safe { @($pagefile | ForEach-Object { "$($_.Name): $($_.AllocatedBaseSize) MB allocated, peak $($_.PeakUsage) MB" }) } @()
$hiberfil = "$env:SystemDrive\hiberfil.sys"
$script:Report['Storage']['Hiberfil'] = Safe { HumanBytes ((Get-Item -LiteralPath $hiberfil -Force -ErrorAction Stop).Length) } 'not present'

# ------------------------------------------------------------ 5. software ---

Section 'Installed software'

$uninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$apps = Safe {
    Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate,
            @{n = 'SizeMB'; e = { if ($_.EstimatedSize) { [Math]::Round($_.EstimatedSize / 1KB, 1) } else { $null } } } |
        Sort-Object DisplayName -Unique
} @()

Say "$($apps.Count) installed programs found"
$bigApps = $apps | Where-Object { $_.SizeMB } | Sort-Object SizeMB -Descending | Select-Object -First 15
foreach ($a in $bigApps | Select-Object -First 8) { Say ("{0,8} MB  {1}" -f $a.SizeMB, $a.DisplayName) }

$store = Safe { Get-AppxPackage -ErrorAction Stop | Measure-Object } $null
$script:Report['Software'] = [ordered]@{
    ProgramCount = $apps.Count
    StoreApps    = if ($store) { $store.Count } else { 'n/a' }
    Largest      = $bigApps
    All          = $apps
}

# Old, likely-abandoned installs
$stale = Safe {
    $apps | Where-Object {
        $_.InstallDate -and $_.InstallDate -match '^\d{8}$' -and
        [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null) -lt (Get-Date).AddYears(-3)
    }
} @()
if ($stale.Count -ge 10) {
    Add-Finding -Severity 'LOW' -Area 'Software' -Title 'Many long-untouched installs' `
        -Detail "$($stale.Count) programs were installed more than 3 years ago and may be unused." `
        -Fix 'Review Settings > Apps and uninstall what you no longer open; old software is also unpatched attack surface.'
}

# Known-risky / EOL software
$riskPatterns = @('Adobe Flash', 'Java 6', 'Java 7', 'Java(TM) 6', 'Java(TM) 7', 'QuickTime',
                  'Python 2', 'Internet Explorer', 'uTorrent', 'McAfee', 'Norton', 'Avast', 'AVG ',
                  'Driver Booster', 'CCleaner', 'WinZip Driver', 'PC Optimizer', 'Advanced SystemCare')
$risky = @($apps | Where-Object { $n = $_.DisplayName; $riskPatterns | Where-Object { $n -like "*$_*" } })
if ($risky.Count -gt 0) {
    Add-Finding -Severity 'MEDIUM' -Area 'Software' -Title 'End-of-life or nuisance software installed' `
        -Detail (($risky | ForEach-Object { $_.DisplayName }) -join '; ') `
        -Fix 'EOL runtimes (Flash, old Java, Python 2) are unpatched. Bundled "optimizers" and duplicate AV suites cost performance and conflict with Defender.'
    Say "Flagged: $(($risky | ForEach-Object { $_.DisplayName }) -join ', ')"
}

# ------------------------------------------------------------- 6. startup ---

Section 'Startup and background load'

$startup = Safe { Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User } @()
$startupFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)
$startupFiles = @()
foreach ($sf in $startupFolders) {
    if (Test-Path -LiteralPath $sf) {
        $startupFiles += Get-ChildItem -LiteralPath $sf -File -Force -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name
    }
}
$logonTasks = Safe {
    Get-ScheduledTask -ErrorAction Stop |
        Where-Object { $_.State -ne 'Disabled' -and ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' }) } |
        Select-Object TaskName, TaskPath
} @()
$autoSvc = Safe {
    Get-CimInstance Win32_Service -Filter "StartMode='Auto'" |
        Select-Object Name, DisplayName, State, PathName
} @()
$thirdPartyAutoSvc = @($autoSvc | Where-Object {
    $_.PathName -and $_.PathName -notmatch [regex]::Escape($env:WINDIR)
})

Say "$($startup.Count) registry/startup-folder entries, $($startupFiles.Count) startup-folder shortcuts"
Say "$($logonTasks.Count) enabled logon/boot scheduled tasks"
Say "$($autoSvc.Count) auto-start services ($($thirdPartyAutoSvc.Count) outside Windows)"

$script:Report['Startup'] = [ordered]@{
    Entries          = $startup
    StartupFolder    = $startupFiles
    LogonTasks       = $logonTasks
    AutoServices     = $autoSvc.Count
    ThirdPartyAuto   = $thirdPartyAutoSvc | Select-Object Name, DisplayName, State
}

$startupLoad = $startup.Count + $startupFiles.Count
if ($startupLoad -gt 20) {
    Add-Finding -Severity 'MEDIUM' -Area 'Startup' -Title 'Heavy startup load' `
        -Detail "$startupLoad programs are set to launch at sign-in." `
        -Fix 'Task Manager > Startup apps: disable anything you do not need in the first five minutes. This is usually the single biggest boot-time win.'
} elseif ($startupLoad -gt 12) {
    Add-Finding -Severity 'LOW' -Area 'Startup' -Title 'Moderate startup load' `
        -Detail "$startupLoad programs launch at sign-in." -Fix 'Trim the ones you rarely use.'
}
if ($thirdPartyAutoSvc.Count -gt 40) {
    Add-Finding -Severity 'LOW' -Area 'Startup' -Title 'Many third-party auto-start services' `
        -Detail "$($thirdPartyAutoSvc.Count) non-Windows services start automatically." `
        -Fix 'Updater and telemetry services from uninstalled-adjacent software accumulate; review services.msc.'
}

# --------------------------------------------------------- 7. performance ---

Section 'Live performance'

$topMem = Safe {
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 `
        Name, Id, @{n = 'MemMB'; e = { [Math]::Round($_.WorkingSet64 / 1MB, 1) } }, `
        @{n = 'CPUsec'; e = { if ($_.CPU) { [Math]::Round($_.CPU, 0) } else { 0 } } }
} @()
foreach ($p in $topMem | Select-Object -First 6) { Say ("{0,8} MB  {1} (pid {2})" -f $p.MemMB, $p.Name, $p.Id) }

$grouped = Safe {
    Get-Process | Group-Object Name |
        Select-Object Name, Count, @{n = 'MemMB'; e = { [Math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 1) } } |
        Sort-Object MemMB -Descending | Select-Object -First 10
} @()

$cpuLoad = Safe { (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average }
Say "CPU load right now: $cpuLoad%"

$script:Report['Performance'] = [ordered]@{
    CpuLoadPct     = $cpuLoad
    TopProcesses   = $topMem
    ByProcessName  = $grouped
}

$bootPerf = Safe {
    Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 5 -ErrorAction Stop |
        ForEach-Object {
            $x = [xml]$_.ToXml()
            [pscustomobject]@{
                Time      = $_.TimeCreated.ToString('yyyy-MM-dd HH:mm')
                BootSec   = [Math]::Round(([double]($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text') / 1000, 1)
            }
        }
} $null
if ($bootPerf) {
    $avgBoot = ($bootPerf | Measure-Object BootSec -Average).Average
    $script:Report['Performance']['RecentBootSeconds'] = $bootPerf
    Say "Recent boot times: $(($bootPerf | ForEach-Object { "$($_.BootSec)s" }) -join ', ')"
    if ($avgBoot -gt 90) {
        Add-Finding -Severity 'MEDIUM' -Area 'Performance' -Title 'Slow boot' `
            -Detail "Average of the last $($bootPerf.Count) boots: $([Math]::Round($avgBoot,1)) seconds." `
            -Fix 'Trim startup apps (above) and confirm the OS is on an SSD, not a spinning disk.'
    }
} elseif (-not $IsAdmin) {
    Say 'Boot-time history needs an elevated run.'
}

# ------------------------------------------------------------ 8. security ---

Section 'Security posture'

$sec = [ordered]@{}

$mp = Safe { Get-MpComputerStatus -ErrorAction Stop }
if ($mp) {
    $sec['DefenderRealtime']      = $mp.RealTimeProtectionEnabled
    $sec['DefenderAntivirus']     = $mp.AntivirusEnabled
    $sec['DefenderSigAgeDays']    = $mp.AntivirusSignatureAge
    $sec['DefenderLastQuickScan'] = Safe { $mp.QuickScanEndTime.ToString('yyyy-MM-dd') } 'never'
    $sec['TamperProtection']      = Safe { $mp.IsTamperProtected } 'n/a'
    Say "Defender realtime: $($mp.RealTimeProtectionEnabled), signatures $($mp.AntivirusSignatureAge) day(s) old"
    if (-not $mp.RealTimeProtectionEnabled) {
        Add-Finding -Severity 'CRITICAL' -Area 'Security' -Title 'Real-time protection is off' `
            -Detail 'Microsoft Defender real-time protection is disabled.' `
            -Fix 'Windows Security > Virus & threat protection > turn Real-time protection back on (unless another AV owns this).'
    }
    if ($mp.AntivirusSignatureAge -gt 7) {
        Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'Antivirus definitions stale' `
            -Detail "Signatures are $($mp.AntivirusSignatureAge) days old." -Fix 'Check for updates in Windows Security.'
    }
} else {
    $av = Safe { Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct } @()
    $sec['AntivirusProducts'] = Safe { @($av | ForEach-Object { $_.displayName }) } @()
    Say "AV products registered: $(($sec['AntivirusProducts']) -join ', ')"
    if (@($av).Count -eq 0) {
        Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'No antivirus product registered' `
            -Detail 'Security Center reports no AV product.' -Fix 'Enable Microsoft Defender.'
    }
}

$fw = Safe { Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled } @()
$sec['Firewall'] = $fw
$fwOff = @($fw | Where-Object { -not $_.Enabled })
if ($fwOff.Count -gt 0) {
    Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'Firewall profile disabled' `
        -Detail ("Disabled profiles: " + (($fwOff | ForEach-Object { $_.Name }) -join ', ')) `
        -Fix 'Windows Security > Firewall & network protection: re-enable. The Public profile especially matters on cafe/airport Wi-Fi.'
} else { Say 'Firewall: enabled on all profiles' }

$bl = Safe { Get-BitLockerVolume -ErrorAction Stop | Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage } @()
if ($bl) {
    $sec['BitLocker'] = $bl
    $sysVol = $bl | Where-Object { $_.MountPoint -eq $env:SystemDrive } | Select-Object -First 1
    Say "BitLocker on $($env:SystemDrive): $(if ($sysVol) { $sysVol.VolumeStatus } else { 'unknown' })"
    if ($sysVol -and $sysVol.ProtectionStatus -ne 'On') {
        Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'System drive is not encrypted' `
            -Detail "BitLocker protection on $($env:SystemDrive) is $($sysVol.ProtectionStatus) (status: $($sysVol.VolumeStatus))." `
            -Fix 'On a laptop holding a personal archive with legal/medical documents, full-disk encryption is the single highest-value fix. Enable BitLocker (Pro) or Device Encryption (Home) and store the recovery key somewhere off the machine.'
    }
} else {
    $sec['BitLocker'] = if ($IsAdmin) { 'unavailable' } else { 'needs admin' }
    Say "BitLocker: $($sec['BitLocker'])"
    if (-not $IsAdmin) {
        Add-Finding -Severity 'INFO' -Area 'Security' -Title 'Encryption status unknown' `
            -Detail 'BitLocker state could not be read without elevation.' `
            -Fix 'Re-run this script as administrator, or check Settings > Privacy & security > Device encryption.'
    }
}

$uacEnabled = Safe { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA).EnableLUA -eq 1 }
$sec['UAC'] = $uacEnabled
if ($uacEnabled -eq $false) {
    Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'UAC disabled' `
        -Detail 'User Account Control is turned off; any process can elevate silently.' -Fix 'Re-enable UAC in Control Panel.'
}

$secureBoot = Safe { Confirm-SecureBootUEFI -ErrorAction Stop } 'unknown'
$sec['SecureBoot'] = $secureBoot
$tpm = Safe { (Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm -ErrorAction Stop | Select-Object -First 1) }
$sec['TPM'] = if ($tpm) { "present, enabled=$($tpm.IsEnabled_InitialValue), activated=$($tpm.IsActivated_InitialValue)" } else { 'not detected / needs admin' }
Say "Secure Boot: $secureBoot | TPM: $($sec['TPM'])"
if ($secureBoot -eq $false) {
    Add-Finding -Severity 'MEDIUM' -Area 'Security' -Title 'Secure Boot disabled' `
        -Detail 'UEFI Secure Boot is off.' -Fix 'Enable in firmware setup unless you dual-boot something that needs it off.'
}

$rdp = Safe { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections).fDenyTSConnections -eq 0 }
$sec['RemoteDesktopEnabled'] = $rdp
if ($rdp -eq $true) {
    Add-Finding -Severity 'MEDIUM' -Area 'Security' -Title 'Remote Desktop is enabled' `
        -Detail 'RDP accepts incoming connections.' `
        -Fix 'Turn it off if you do not use it (Settings > System > Remote Desktop). RDP is a top-three ransomware entry point.'
}

$smb1 = Safe { (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop).State } 'unknown'
$sec['SMB1'] = $smb1
if ($smb1 -eq 'Enabled') {
    Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'SMBv1 enabled' `
        -Detail 'The obsolete SMBv1 protocol is installed and enabled.' `
        -Fix 'Remove it: Turn Windows features on or off > uncheck SMB 1.0/CIFS.'
}

$admins = Safe { Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop | Select-Object Name, ObjectClass } @()
$sec['LocalAdmins'] = Safe { @($admins | ForEach-Object { $_.Name }) } @()
Say "Local administrators: $(($sec['LocalAdmins']) -join ', ')"

$noPwd = Safe { Get-LocalUser -ErrorAction Stop | Where-Object { $_.Enabled -and -not $_.PasswordRequired } | Select-Object -ExpandProperty Name } @()
if (@($noPwd).Count -gt 0) {
    Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'Enabled account without a required password' `
        -Detail ("Accounts: " + ($noPwd -join ', ')) -Fix 'Set a password or disable the account.'
}

$lastHotfix = Safe { Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1 }
$sec['LastUpdate'] = Safe { $lastHotfix.InstalledOn.ToString('yyyy-MM-dd') } 'unknown'
$sec['HotfixCount'] = Safe { (Get-HotFix | Measure-Object).Count } 0
Say "Last update installed: $($sec['LastUpdate'])"
if ($lastHotfix -and $lastHotfix.InstalledOn -lt (Get-Date).AddDays(-60)) {
    Add-Finding -Severity 'HIGH' -Area 'Security' -Title 'Windows updates look stale' `
        -Detail "Most recent hotfix installed $($sec['LastUpdate'])." `
        -Fix 'Settings > Windows Update > Check for updates. Monthly patches close actively exploited holes.'
}

$script:Report['Security'] = $sec

# ------------------------------------------------------------- 9. network ---

Section 'Network'

$adapters = Safe { Get-NetAdapter -ErrorAction Stop | Where-Object Status -eq 'Up' |
    Select-Object Name, InterfaceDescription, LinkSpeed, MacAddress } @()
foreach ($a in $adapters) { Say "$($a.Name): $($a.InterfaceDescription) @ $($a.LinkSpeed)" }

$dns = Safe { Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
    Where-Object { $_.ServerAddresses } | Select-Object InterfaceAlias, ServerAddresses } @()

$listening = Safe {
    Get-NetTCPConnection -State Listen -ErrorAction Stop |
        Select-Object LocalAddress, LocalPort, OwningProcess -Unique |
        ForEach-Object {
            $pn = Safe { (Get-Process -Id $_.OwningProcess -ErrorAction Stop).Name } 'unknown'
            [pscustomobject]@{ Address = $_.LocalAddress; Port = $_.LocalPort; Process = $pn }
        } | Sort-Object Port
} @()
$publicListen = @($listening | Where-Object { $_.Address -eq '0.0.0.0' -or $_.Address -eq '::' })
Say "$($listening.Count) listening TCP sockets, $($publicListen.Count) bound to all interfaces"

$proxy = Safe { Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
    Select-Object ProxyEnable, ProxyServer, AutoConfigURL }
if ($proxy -and $proxy.ProxyEnable -eq 1) {
    Say "System proxy enabled: $($proxy.ProxyServer)"
    Add-Finding -Severity 'INFO' -Area 'Network' -Title 'System proxy configured' `
        -Detail "Proxy: $($proxy.ProxyServer) | PAC: $($proxy.AutoConfigURL)" `
        -Fix 'Expected if you set it. An unexplained proxy is a classic adware/interception artefact - verify you configured it.'
}

$wifiProfiles = Safe { (netsh wlan show profiles) -match 'All User Profile' } @()
$script:Report['Network'] = [ordered]@{
    Adapters        = $adapters
    DNS             = $dns
    ListeningPorts  = $listening
    PublicListeners = $publicListen
    SavedWifi       = @($wifiProfiles).Count
    Proxy           = $proxy | Select-Object ProxyEnable, ProxyServer, AutoConfigURL
}

# --------------------------------------------------- 10. developer setup ---

Section 'Developer toolchain'

$tools = @('git', 'node', 'npm', 'python', 'py', 'pwsh', 'code', 'docker', 'java', 'gh', 'rg', 'ffmpeg')
$toolInfo = @()
foreach ($t in $tools) {
    $cmd = Safe { Get-Command $t -ErrorAction Stop | Select-Object -First 1 }
    if ($cmd) {
        $ver = switch ($t) {
            'java'   { Safe { (& $t -version 2>&1 | Select-Object -First 1) -join ' ' } 'unknown' }
            'code'   { Safe { (& $t --version 2>$null | Select-Object -First 1) } 'unknown' }
            default  { Safe { (& $t --version 2>$null | Select-Object -First 1) } 'unknown' }
        }
        $toolInfo += [pscustomobject]@{ Tool = $t; Version = "$ver"; Path = $cmd.Source }
        Say ("{0,-8} {1}" -f $t, $ver)
    }
}

# PATH hygiene
$pathUser    = Safe { [Environment]::GetEnvironmentVariable('Path', 'User') } ''
$pathMachine = Safe { [Environment]::GetEnvironmentVariable('Path', 'Machine') } ''
$pathEntries = ($env:Path -split ';') | Where-Object { $_ -and $_.Trim() }
$pathMissing = @($pathEntries | Where-Object { -not (Test-Path -LiteralPath $_.Trim() -ErrorAction SilentlyContinue) })
$pathDupes   = @($pathEntries | Group-Object { $_.TrimEnd('\').ToLower() } | Where-Object Count -gt 1 | ForEach-Object { $_.Name })

Say "PATH: $($pathEntries.Count) entries, $($pathMissing.Count) missing, $($pathDupes.Count) duplicated"
if ($pathMissing.Count -gt 0) {
    Add-Finding -Severity 'LOW' -Area 'Dev' -Title 'PATH contains dead directories' `
        -Detail ("Missing: " + (($pathMissing | Select-Object -First 10) -join '; ')) `
        -Fix 'Every miss costs a filesystem probe on each command lookup. Clean them out of the environment variables editor.'
}
if ($pathDupes.Count -gt 0) {
    Add-Finding -Severity 'LOW' -Area 'Dev' -Title 'Duplicate PATH entries' `
        -Detail ($pathDupes -join '; ') -Fix 'Deduplicate; duplicates usually mean a repeated installer run.'
}
if ($pathUser.Length -gt 1800) {
    Add-Finding -Severity 'MEDIUM' -Area 'Dev' -Title 'User PATH near the length limit' `
        -Detail "User PATH is $($pathUser.Length) characters; the legacy limit is 2047 and installers silently truncate past it." `
        -Fix 'Prune entries before the next SDK install corrupts it.'
}

$script:Report['Dev'] = [ordered]@{
    Tools          = $toolInfo
    PathEntries    = $pathEntries.Count
    PathMissing    = $pathMissing
    PathDuplicates = $pathDupes
    UserPathLength = $pathUser.Length
    GitUser        = Safe { (& git config --global user.name) } 'not set'
    GitEmail       = Safe { (& git config --global user.email) } 'not set'
}

# --------------------------------------------------------- 11. reliability ---

Section 'Reliability'

$errs = Safe {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop |
        Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 10 Count, Name
} @()
foreach ($e in $errs | Select-Object -First 5) { Say ("{0,5}x  {1}" -f $e.Count, $e.Name) }

$appErrs = Safe {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop |
        Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 10 Count, Name
} @()

$minidumps = Safe { @(Get-ChildItem "$env:WINDIR\Minidump" -Filter *.dmp -ErrorAction Stop |
    Sort-Object LastWriteTime -Descending | Select-Object Name, LastWriteTime) } @()
$memdump = Safe { (Get-Item "$env:WINDIR\MEMORY.DMP" -ErrorAction Stop) }

$script:Report['Reliability'] = [ordered]@{
    SystemErrors7d      = $errs
    ApplicationErrors7d = $appErrs
    Minidumps           = $minidumps
    MemoryDump          = if ($memdump) { "$(HumanBytes $memdump.Length) dated $($memdump.LastWriteTime.ToString('yyyy-MM-dd'))" } else { 'none' }
}

$recentDumps = @($minidumps | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) })
if ($recentDumps.Count -gt 0) {
    Add-Finding -Severity 'HIGH' -Area 'Reliability' -Title 'Recent crash dumps (blue screens)' `
        -Detail "$($recentDumps.Count) minidump(s) in the last 30 days, most recent $($recentDumps[0].LastWriteTime.ToString('yyyy-MM-dd'))." `
        -Fix 'Open the dumps with WhoCrashed/WinDbg, or start with a memory test (mdsched.exe) and GPU/storage driver updates.'
    Say "$($recentDumps.Count) crash dump(s) in the last 30 days"
}
$totalSysErr = ($errs | Measure-Object Count -Sum).Sum
if ($totalSysErr -gt 200) {
    Add-Finding -Severity 'MEDIUM' -Area 'Reliability' -Title 'High system error volume' `
        -Detail "$totalSysErr System-log errors in the last 7 days, led by $($errs[0].Name) ($($errs[0].Count))." `
        -Fix 'Investigate the top provider; a repeating driver or service error usually explains hangs and slow boots.'
}
if (-not $IsAdmin -and @($errs).Count -eq 0) { Say 'Event log detail may need an elevated run.' }

# ------------------------------------------------------------ 12. backup ---

Section 'Backup and sync'

$oneDrive = $env:OneDrive
$sync = [ordered]@{
    OneDrivePath      = if ($oneDrive) { $oneDrive } else { 'not configured' }
    DesktopRedirected = Safe { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name Desktop).Desktop } 'unknown'
    DocsRedirected    = Safe { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name Personal).Personal } 'unknown'
    FileHistory       = Safe { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FileHistory' -ErrorAction Stop) -ne $null } $false
    RestorePoints     = Safe { @(Get-ComputerRestorePoint -ErrorAction Stop | Select-Object -Last 3 Description, @{n='When';e={$_.ConvertToDateTime($_.CreationTime).ToString('yyyy-MM-dd')}}) } 'needs admin'
}
Say "OneDrive: $($sync.OneDrivePath)"
Say "File History configured: $($sync.FileHistory)"
$script:Report['Backup'] = $sync

if (-not $oneDrive -and $sync.FileHistory -eq $false) {
    Add-Finding -Severity 'HIGH' -Area 'Backup' -Title 'No backup mechanism detected' `
        -Detail 'Neither OneDrive folder redirection nor File History appears configured.' `
        -Fix 'A laptop holding an irreplaceable personal archive needs at least one automated copy off the device. Note: cloud-syncing sensitive documents unredacted has its own risks - an encrypted external drive is the safer default for that material.'
}

# ------------------------------------------------------- 13. deep scans ----

if ($Deep) {
    Section "Deep scan (files over $LargeFileMB MB, duplicates)"
    Say 'Walking the user profile. This can take several minutes...'

    $allFiles = Get-ChildItem -LiteralPath $env:USERPROFILE -Recurse -File -Force -ErrorAction SilentlyContinue

    $large = $allFiles | Where-Object { $_.Length -gt ($LargeFileMB * 1MB) } |
        Sort-Object Length -Descending | Select-Object -First 40 |
        ForEach-Object { [pscustomobject]@{ Size = HumanBytes $_.Length; Bytes = $_.Length; Path = $_.FullName } }
    foreach ($f in $large | Select-Object -First 10) { Say ("{0,-10} {1}" -f $f.Size, $f.Path) }

    Say 'Hashing same-size candidates for duplicates...'
    $dupGroups = $allFiles | Where-Object { $_.Length -gt 10MB } | Group-Object Length | Where-Object Count -gt 1
    $dupes = @()
    foreach ($g in $dupGroups) {
        $hashes = $g.Group | ForEach-Object {
            $h = Safe { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
            if ($h) { [pscustomobject]@{ Hash = $h; Path = $_.FullName; Length = $_.Length } }
        }
        foreach ($hg in ($hashes | Group-Object Hash | Where-Object Count -gt 1)) {
            $dupes += [pscustomobject]@{
                Size      = HumanBytes $hg.Group[0].Length
                Wasted    = HumanBytes ($hg.Group[0].Length * ($hg.Count - 1))
                WastedB   = $hg.Group[0].Length * ($hg.Count - 1)
                Copies    = $hg.Count
                Paths     = @($hg.Group | ForEach-Object { $_.Path })
            }
        }
    }
    $dupes = $dupes | Sort-Object WastedB -Descending | Select-Object -First 30
    $wastedTotal = ($dupes | Measure-Object WastedB -Sum).Sum
    Say "$($dupes.Count) duplicate sets over 10 MB, wasting $(HumanBytes ([double]$wastedTotal))"

    $script:Report['DeepScan'] = [ordered]@{
        LargeFiles     = $large
        DuplicateSets  = $dupes
        DuplicateWaste = HumanBytes ([double]$wastedTotal)
    }
    if ($wastedTotal -gt 10GB) {
        Add-Finding -Severity 'MEDIUM' -Area 'Storage' -Title 'Significant duplicate data' `
            -Detail "$(HumanBytes ([double]$wastedTotal)) held in duplicate copies of files over 10 MB." `
            -Fix 'Review the duplicate list before deleting - keep one copy of anything archival, and never delete the only copy of a source export.'
    }
} else {
    Say 'Skipping large-file and duplicate scan (re-run with -Deep to include it).'
}

# ------------------------------------------------------------- 14. report ---

Section 'Report'

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $env:USERPROFILE 'Desktop'
    if (-not (Test-Path -LiteralPath $OutDir)) { $OutDir = $env:USERPROFILE }
}
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$stamp    = (Get-Date).ToString('yyyy-MM-dd_HHmm')
$base     = Join-Path $OutDir ("laptop-audit_{0}_{1}" -f $env:COMPUTERNAME, $stamp)
$mdPath   = "$base.md"
$jsonPath = "$base.json"

$sevOrder = @{ 'CRITICAL' = 0; 'HIGH' = 1; 'MEDIUM' = 2; 'LOW' = 3; 'INFO' = 4 }
$sorted   = @($script:Findings | Sort-Object { $sevOrder[$_.Severity] }, Area)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Laptop audit - $env:COMPUTERNAME")
[void]$sb.AppendLine()
[void]$sb.AppendLine("Generated $((Get-Date).ToString('yyyy-MM-dd HH:mm')) | elevated: $IsAdmin | deep scan: $($Deep.IsPresent) | runtime: $([Math]::Round(((Get-Date) - $script:Started).TotalSeconds,1))s")
[void]$sb.AppendLine()
[void]$sb.AppendLine('## Findings')
[void]$sb.AppendLine()
if ($sorted.Count -eq 0) {
    [void]$sb.AppendLine('Nothing flagged. Everything checked came back within normal thresholds.')
} else {
    foreach ($sev in @('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO')) {
        $group = @($sorted | Where-Object { $_.Severity -eq $sev })
        if ($group.Count -eq 0) { continue }
        [void]$sb.AppendLine("### $sev ($($group.Count))")
        [void]$sb.AppendLine()
        foreach ($f in $group) {
            [void]$sb.AppendLine("- **[$($f.Area)] $($f.Title)**")
            [void]$sb.AppendLine("  - $($f.Detail)")
            if ($f.Fix) { [void]$sb.AppendLine("  - Fix: $($f.Fix)") }
        }
        [void]$sb.AppendLine()
    }
}

foreach ($key in $script:Report.Keys) {
    [void]$sb.AppendLine("## $key")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine((($script:Report[$key] | Format-List | Out-String).Trim()))
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine()
}

[void]$sb.AppendLine('---')
[void]$sb.AppendLine('This report lists your hostname, user name, installed software, network configuration and file paths. Review before sharing it.')

Set-Content -LiteralPath $mdPath -Value $sb.ToString() -Encoding UTF8
$script:Report['Findings'] = $sorted
$script:Report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host ''
Write-Host ' SUMMARY ' -ForegroundColor Black -BackgroundColor Yellow
foreach ($sev in @('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO')) {
    $n = @($script:Findings | Where-Object { $_.Severity -eq $sev }).Count
    if ($n -eq 0) { continue }
    $color = switch ($sev) { 'CRITICAL' { 'Red' } 'HIGH' { 'Red' } 'MEDIUM' { 'Yellow' } 'LOW' { 'Gray' } default { 'DarkGray' } }
    Write-Host ("  {0,-9} {1}" -f $sev, $n) -ForegroundColor $color
    foreach ($f in ($script:Findings | Where-Object { $_.Severity -eq $sev })) {
        Write-Host ("      - [{0}] {1}" -f $f.Area, $f.Title) -ForegroundColor $color
    }
}
Write-Host ''
Write-Host "  Markdown: $mdPath" -ForegroundColor Green
Write-Host "  JSON:     $jsonPath" -ForegroundColor Green
Write-Host ''
Write-Host '  Nothing was changed on this machine.' -ForegroundColor DarkGray
if (-not $IsAdmin) {
    Write-Host '  Some checks (BitLocker, TPM, boot timings, full event log) need an elevated run.' -ForegroundColor DarkGray
}
Write-Host ''
