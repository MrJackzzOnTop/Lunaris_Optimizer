Clear-Host
if ($env:OS -ne "Windows_NT") {
    Write-Host "[!] Lunaris Optimizer requires Windows OS to function properly!" -ForegroundColor Red
    return
}
function Confirm-Action {
    param(
        [string]$Message
    )

    while ($true) {
        Write-Host "[?] $Message (y/N): " -ForegroundColor Cyan -NoNewLine

        $answer = (Read-Host).Trim().ToLower()

        if ($answer -in @("y", "yes")) {
             return $true
        }
        elseif ($answer -in @("n", "no", "")) {
            return $false
        }
        else {
            Write-Host "[!] Invalid choice. Please enter Y or N." -ForegroundColor Red
        }
    }
}
function Get-SafeFiles {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    # Traverse regular directories only; never follow junctions or symlinks.
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Path)
    $found = New-Object 'System.Collections.Generic.List[object]'
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            else { [void]$found.Add($item) }
        }
    }
    return $found.ToArray()
}

function Get-TempInfo {
    param([string]$Path)
    Write-Host "`n[*] Scanning directory: $Path" -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Host '[!] Directory not found!' -ForegroundColor Red
        return
    }
    $files = @(Get-SafeFiles -Path $Path)
    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    $totalMB = [math]::Round($totalBytes / 1MB, 2)
    $totalGB = [math]::Round($totalBytes / 1GB, 2)
    Write-Host "[+] Files found: $($files.Count)" -ForegroundColor Green
    Write-Host "[+] Total size: $totalMB MB ($totalGB GB)" -ForegroundColor Green
}

function Clear-DirectoryFiles {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Host "[!] $Label directory not found!" -ForegroundColor Red
        return
    }
    $files = @(Get-SafeFiles -Path $Path)
    Write-Host "[*] $Label files found: $($files.Count)" -ForegroundColor Yellow
    if ($files.Count -eq 0) { Write-Host '[i] No files to clean.' -ForegroundColor Yellow; return }
    if (-not (Confirm-Action "Do you want to delete $Label files (including subfolders)?")) {
        Write-Host "[-] $Label cleanup cancelled." -ForegroundColor Yellow
        return
    }
    $deleted = 0
    $skipped = 0
    foreach ($file in $files) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $deleted++
        }
        catch { $skipped++ }
    }
    # Empty folders are left in place; this avoids traversing junctions or symlinks.
    Write-Host "[+] Files deleted: $deleted" -ForegroundColor Green
    Write-Host "[i] Files skipped or failed: $skipped" -ForegroundColor Yellow
}

function Clear-UserTemp {
    $tempPath = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempPath) -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Write-Host '[!] User TEMP directory unavailable!' -ForegroundColor Red
        return
    }
    $expectedPath = Join-Path $env:LOCALAPPDATA 'Temp'
    $actualPath = [System.IO.Path]::GetFullPath($tempPath).TrimEnd('\')
    $safePath = [System.IO.Path]::GetFullPath($expectedPath).TrimEnd('\')
    if ($actualPath -ine $safePath) {
        Write-Host '[!] Unexpected TEMP directory. Cleanup cancelled.' -ForegroundColor Red
        return
    }
    Clear-DirectoryFiles -Path $actualPath -Label 'User TEMP'
}

function Clear-WindowsTemp {
    $windowsTemp = Join-Path $env:windir 'Temp'
    Clear-DirectoryFiles -Path $windowsTemp -Label 'Windows TEMP'
}

function Clear-Prefetch {
    $prefetchPath = Join-Path $env:windir 'Prefetch'
    Write-Host '[i] Prefetch is a Windows performance cache; Windows will recreate it.' -ForegroundColor Yellow
    Clear-DirectoryFiles -Path $prefetchPath -Label 'Prefetch'
}

function Get-EventLogInfo {
    Write-Host "`n[*] Scanning Windows Event Logs..." -ForegroundColor Yellow
    foreach ($logName in @('System', 'Application')) {
        try {
            $errors = @(Get-WinEvent -FilterHashtable @{
                LogName = $logName
                Level = 2
                StartTime = (Get-Date).AddDays(-1)
            } -MaxEvents 10 -ErrorAction Stop)
            Write-Host "[+] $logName recent errors shown: $($errors.Count)" -ForegroundColor Green
            foreach ($event in $errors) {
                Write-Host "[i] $($event.TimeCreated) - ID $($event.Id) - $($event.ProviderName)" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "[i] No matching events or unable to read: $logName" -ForegroundColor Yellow
        }
    }
}

function Clear-EventLogsWithBackup {
    Write-Host '[i] Clearing event logs does not improve FPS.' -ForegroundColor Yellow
    Write-Host '[i] Security contains security audit records and will be backed up, not cleared.' -ForegroundColor Yellow
    if (-not (Confirm-Action 'Do you want to back up Windows Logs and clear Application, Setup, System, and Forwarded Events?')) {
        Write-Host '[-] Event Log cleanup cancelled.' -ForegroundColor Yellow
        return
    }

    $backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('Lunaris-EventLog-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host '[!] Could not create backup directory. Logs will NOT be cleared.' -ForegroundColor Red
        return
    }

    foreach ($logName in @('Application', 'Security', 'Setup', 'System', 'ForwardedEvents')) {
        $backupPath = Join-Path $backupRoot "$logName.evtx"
        & wevtutil.exe epl $logName $backupPath 2>$null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupPath) -or (Get-Item -LiteralPath $backupPath).Length -eq 0) {
            Write-Host "[!] $logName backup failed. Log preserved." -ForegroundColor Yellow
            continue
        }
        if ($logName -eq 'Security') {
            Write-Host "[i] Security backed up and preserved: $backupPath" -ForegroundColor Cyan
            continue
        }
        & wevtutil.exe cl $logName 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[+] $logName cleared. Backup: $backupPath" -ForegroundColor Green
        }
        else {
            Write-Host "[!] Unable to clear $logName. Backup kept." -ForegroundColor Yellow
        }
    }
}

function Clear-RecycleBinSafe {
    if (-not (Confirm-Action "Do you want to clear the Recycle Bin?")) {
        Write-Host "[-] Recycle Bin cleanup cancelled." -ForegroundColor Yellow
        return
    }
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "[+] Recycle Bin cleared successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "[!] Recycle Bin cleanup request sent." -ForegroundColor Yellow
    }
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[?] Requesting administrator privileges..." -ForegroundColor Cyan

    try {
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -NoExit -File `"$PSCommandPath`"" `
            -WorkingDirectory (Split-Path -Parent $PSCommandPath) `
            -Verb RunAs `
            -ErrorAction Stop

        exit
    }
    catch {
        Write-Host "[!] ERROR: Administrator privileges were denied or cancelled." -ForegroundColor Red
        Write-Host "[!] Lunaris Optimizer cannot perform administrator-only operations." -ForegroundColor Red
        return
    }
}
Clear-Host
$banner = @"

 ▄▄▌  ▄• ▄▌ ▐ ▄  ▄▄▄· ▄▄▄  ▪  .▄▄ ·            ▄▄▄·▄▄▄▄▄▪  • ▌ ▄ ·. ▪  ·▄▄▄▄•▄▄▄ .▄▄▄
 ██•  █▪██▌•█▌▐█▐█ ▀█ ▀▄ █·██ ▐█ ▀.     ▪     ▐█ ▄█•██  ██ ·██ ▐███▪██ ▪▀·.█▌▀▄.▀·▀▄ █·
 ██▪  █▌▐█▌▐█▐▐▌▄█▀▀█ ▐▀▀▄ ▐█·▄▀▀▀█▄     ▄█▀▄  ██▀· ▐█.▪▐█·▐█ ▌▐▌▐█·▐█·▄█▀▀▀•▐▀▀▪▄▐▀▀▄
 ▐█▌▐▌▐█▄█▌██▐█▌▐█ ▪▐▌▐█•█▌▐█▌▐█▄▪▐█    ▐█▌.▐▌▐█▪·• ▐█▌·▐█▌██ ██▌▐█▌▐█▌█▌▪▄█▀▐█▄▄▌▐█•█▌
 .▀▀▀  ▀▀▀ ▀▀ █▪ ▀  ▀ .▀  ▀▀▀▀ ▀▀▀▀      ▀█▄▀▪.▀    ▀▀▀ ▀▀▀▀▀  █▪▀▀▀▀▀▀·▀▀▀ • ▀▀▀ .▀  ▀

"@
$credits = @"

                        _________________________________
                       |                                 |
                       |  URL: https://lunaristeam.net   |
                       |      Author: MrJackzzOnTop      |
                       |_________________________________|


"@
Write-Host $banner -ForegroundColor Magenta
Write-Host $credits -ForegroundColor Red
Start-Sleep -Milliseconds 700
Write-Host "[+] Welcome to Lunaris Optimizer made by LunarisTeam. `n`n[!] Before optimizing your Windows OS, make sure that you have been downloaded`nthis file from lunaristeam.net, otherwise, it may be something else.`n" -ForegroundColor DarkYellow
Start-Sleep -Seconds 1
Write-Host "[+] Lunaris Optimizer is not an FPS tweaker. It cleans temporary files and can back up`nand clear selected Windows event logs." -ForegroundColor Cyan
if (Confirm-Action "Do you want to continue? The program will ask everytime before making changes.") {
    Write-Host "[+] Continue request confirmed by the user." -ForegroundColor Green
}
else {
    Write-Host "[!] Continue request cancelled by the user." -ForegroundColor Red
    return
}
Start-Sleep -Seconds 1
Write-Host "[+] Loading Lunaris Optimizer..." -ForegroundColor Yellow
Start-Sleep -Milliseconds 700
Write-Host "`n[+] Starting cleanup module..." -ForegroundColor Green
if (Confirm-Action "Do you want to scan User TEMP files?") {
    Write-Host "[+] User TEMP scan confirmed by the user!" -ForegroundColor Green
    Get-TempInfo -Path $env:TEMP
    Clear-UserTemp
}
else {
    Write-Host "[-] User TEMP scan skipped." -ForegroundColor Yellow
}
if (Confirm-Action "Do you want to scan Windows TEMP files?") {
    Write-Host "[+] Windows TEMP scan confirmed by the user!" -ForegroundColor Green
    $windowsTemp = Join-Path $env:windir "Temp"
    Get-TempInfo -Path $windowsTemp
    Clear-WindowsTemp
}
else {
    Write-Host "[-] Windows TEMP scan skipped." -ForegroundColor Yellow
}
if (Confirm-Action "Do you want to scan Prefetch files?") {
    Write-Host "[+] Prefetch scan confirmed by the user!" -ForegroundColor Green
    $prefetchPath = Join-Path $env:windir "Prefetch"
    Get-TempInfo -Path $prefetchPath
    Clear-Prefetch
}
else {
    Write-Host "[-] Prefetch scan skipped." -ForegroundColor Yellow
}
if (Confirm-Action "Do you want to view Windows Log information?") {
    Write-Host "[+] EVENTVWR Log information selected." -ForegroundColor Green
    Get-EventLogInfo
    Clear-EventLogsWithBackup
}
else {
    Write-Host "[-] Event Log information scan skipped." -ForegroundColor Yellow
}
Clear-RecycleBinSafe
Write-Host "`n[+] Lunaris Optimizer finished! Thanks for using this tool, you can search more on lunaristeam.net" -ForegroundColor Green
