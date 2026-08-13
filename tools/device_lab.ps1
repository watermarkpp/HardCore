[CmdletBinding()]
param(
    [ValidateSet('push', 'status', 'snapshot', 'apply_ui_profile', 'export_player_state', 'apply_player_state', 'list_checkpoints', 'rollback_player_state', 'rollback_ui_profile', 'pull', 'screenshot')]
    [string]$Action = 'status',
    [ValidatePattern('^$|^[A-Za-z0-9._:-]{1,128}$')]
    [string]$Serial = '',
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')]
    [string]$PackageId = 'com.personal.mafaoffline',
    [string]$Profile = '',
    [string]$LayoutPath = '',
    [string]$PayloadPath = '',
    [string]$Checkpoint = '',
    [string]$Nonce = '',
    [string]$OutputPath = '',
    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 20,
    [string]$Adb = 'adb'
)

$ErrorActionPreference = 'Stop'
$DeviceLabPrivateRoot = 'files/device_lab'

function Invoke-Adb {
    param([string[]]$Arguments)
    $args = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) { $args += @('-s', $Serial) }
    $args += $Arguments
    $output = & $Adb @args
    if ($LASTEXITCODE -ne 0) { throw "adb failed ($LASTEXITCODE): $($output -join "`n")" }
    return $output
}

function Get-SafeNonce {
    if ([string]::IsNullOrWhiteSpace($Nonce)) {
        return ([Guid]::NewGuid().ToString('N'))
    }
    if ($Nonce -notmatch '^[A-Za-z0-9_.-]{1,64}$') { throw "Nonce contains unsafe characters: $Nonce" }
    return $Nonce
}

function Assert-SafeRemoteName {
    param([string]$Name)
    if ($Name -notmatch '^[A-Za-z0-9_.-]{1,128}$' -or $Name.Contains('..')) {
        throw "Unsafe Device Lab remote name: $Name"
    }
}

function Invoke-RunAs {
    param([string[]]$Arguments)
    $prefix = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) { $prefix += @('-s', $Serial) }
    $prefix += @('shell', 'run-as', $PackageId)
    $result = & $Adb @prefix @Arguments
    if ($LASTEXITCODE -ne 0) { throw "adb run-as failed ($LASTEXITCODE): $($result -join "`n")" }
    return $result
}

function Invoke-RunAsCapture {
    param([string[]]$Arguments)
    # This is intentionally limited to fixed, validated Device Lab paths and
    # tokens.  Unlike Invoke-RunAs it preserves the exit code so mkdir/test
    # can distinguish a busy lock from an adb/run-as failure.
    $prefix = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) { $prefix += @('-s', $Serial) }
    $prefix += @('shell', 'run-as', $PackageId)
    $result = @(& $Adb @prefix @Arguments 2>&1)
    [pscustomobject]@{
        ExitCode = [int]$LASTEXITCODE
        Output = $result
    }
}

function Invoke-RunAsText {
    param([string[]]$Arguments)
    $lines = Invoke-RunAs -Arguments $Arguments
    return ($lines -join "`n").Trim()
}

function Ensure-DeviceLabDirs {
    [void](Invoke-RunAs -Arguments @('mkdir', '-p', "$DeviceLabPrivateRoot/inbox", "$DeviceLabPrivateRoot/outbox"))
}

function Test-RemoteFile {
    param([string]$Path)
    if ($Path -notmatch '^files/device_lab/(inbox/(pending|processing)\.json|outbox/result_[A-Za-z0-9_.-]{1,64}\.json)$') {
        throw "Unsafe fixed Device Lab path: $Path"
    }
    try {
        [void](Invoke-RunAs -Arguments @('ls', $Path))
        return $true
    } catch {
        return $false
    }
}

function Test-DeviceLabInboxBusy {
    return (Test-RemoteFile -Path "$DeviceLabPrivateRoot/inbox/pending.json") -or (Test-RemoteFile -Path "$DeviceLabPrivateRoot/inbox/processing.json")
}

function Test-RemoteInboxEntry {
    param([string]$Name)
    Assert-SafeRemoteName -Name $Name
    $path = "$DeviceLabPrivateRoot/inbox/$Name"
    $probe = Invoke-RunAsCapture -Arguments @('test', '-e', $path)
    if ($probe.ExitCode -eq 0) { return $true }
    if ($probe.ExitCode -eq 1) { return $false }
    throw "Unable to inspect fixed Device Lab inbox entry: $Name ($($probe.Output -join "`n"))"
}

function Enter-DeviceLabLock {
    $lockPath = "$DeviceLabPrivateRoot/inbox/.lock"
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        $attempt = Invoke-RunAsCapture -Arguments @('mkdir', $lockPath)
        if ($attempt.ExitCode -eq 0) { return $true }

        # mkdir is the atomic mutex.  A failed mkdir is only treated as
        # contention when the lock is demonstrably present; transport or
        # permission failures are surfaced instead of being misreported as a
        # busy mailbox.
        $probe = Invoke-RunAsCapture -Arguments @('test', '-d', $lockPath)
        if ($probe.ExitCode -ne 0) {
            throw "Unable to acquire Device Lab mailbox lock ($($attempt.Output -join "`n"))"
        }
        Start-Sleep -Milliseconds 50
    }
    throw 'Timed out waiting for Device Lab mailbox lock'
}

function New-CommandFile {
    param([hashtable]$Command, [string]$Path)
    $json = $Command | ConvertTo-Json -Depth 40 -Compress
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Push-HostFile {
    param([string]$LocalPath, [string]$RemoteInboxName, [string]$NonceValue)
    Assert-SafeRemoteName -Name $RemoteInboxName
    if ([string]::IsNullOrWhiteSpace($NonceValue) -or $NonceValue -notmatch '^[A-Za-z0-9_.-]{1,64}$') {
        throw 'Device Lab stage nonce is unsafe'
    }
    $resolved = (Resolve-Path -LiteralPath $LocalPath -ErrorAction Stop).Path
    $transferToken = [Guid]::NewGuid().ToString('N')
    $temporary = "/data/local/tmp/hardcore_device_lab_${NonceValue}_$transferToken.tmp"
    $stageName = ".stage_${NonceValue}_$transferToken.tmp"
    Assert-SafeRemoteName -Name $stageName
    $stagePath = "$DeviceLabPrivateRoot/inbox/$stageName"
    $lockOwner = $false
    try {
        Invoke-Adb -Arguments @('push', $resolved, $temporary) | Out-Null
        Ensure-DeviceLabDirs
        # The lock is acquired before creating the inbox stage, so a contender
        # never leaves a stage behind that it does not own.
        $lockOwner = Enter-DeviceLabLock
        if (Test-DeviceLabInboxBusy) {
            throw 'Device Lab mailbox is busy; refusing to overwrite pending/processing command'
        }
        if (Test-RemoteInboxEntry -Name $RemoteInboxName) {
            throw "Device Lab inbox entry already exists; refusing overwrite: $RemoteInboxName"
        }
        [void](Invoke-RunAs -Arguments @('cp', $temporary, $stagePath))
        # Re-check under the same lock immediately before the atomic rename.
        if (Test-DeviceLabInboxBusy) {
            throw 'Device Lab mailbox became busy before atomic move'
        }
        $move = Invoke-RunAsCapture -Arguments @('mv', $stagePath, "$DeviceLabPrivateRoot/inbox/$RemoteInboxName")
        if ($move.ExitCode -ne 0) {
            throw "Device Lab atomic move failed ($($move.Output -join "`n"))"
        }
    } finally {
        if ($lockOwner) {
            # Only the mkdir owner may remove the lock or its unique stage.
            try { Invoke-RunAs -Arguments @('rm', '-f', $stagePath) | Out-Null } catch { }
            try { Invoke-RunAs -Arguments @('rmdir', "$DeviceLabPrivateRoot/inbox/.lock") | Out-Null } catch { }
        }
        try { Invoke-Adb -Arguments @('shell', 'rm', '-f', $temporary) | Out-Null } catch { }
    }
}

function Push-Command {
    param([hashtable]$Command)
    $nonceValue = [string]$Command.nonce
    $hostTemp = Join-Path ([IO.Path]::GetTempPath()) "hardcore_device_lab_$nonceValue.json"
    try {
        New-CommandFile -Command $Command -Path $hostTemp
        Push-HostFile -LocalPath $hostTemp -RemoteInboxName 'pending.json' -NonceValue $nonceValue
    } finally {
        if (Test-Path -LiteralPath $hostTemp) { Remove-Item -LiteralPath $hostTemp -Force }
    }
}

function Read-Result {
    param([string]$NonceValue)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    Assert-SafeRemoteName -Name $NonceValue
    $remote = "$DeviceLabPrivateRoot/outbox/result_$NonceValue.json"
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $text = Invoke-RunAsText -Arguments @('cat', $remote)
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $result = $text | ConvertFrom-Json
                if ([int]$result.protocolVersion -ne 1 -or [string]$result.nonce -ne $NonceValue) {
                    throw 'Device Lab result identity validation failed'
                }
                return $result
            }
        } catch {
            # The file does not exist yet; keep polling at the mailbox cadence.
        }
        Start-Sleep -Milliseconds 150
    }
    throw "Timed out waiting for Device Lab result: $remote"
}

function New-ApplyCommand {
    param([string]$NonceValue)
    if ($Profile -notmatch '^(character_hall|confirmation_dialog|death_revival|inventory|map|quest|shop_buy|shop_sell|skill|system_menu|warehouse)$') {
        throw "Profile is not in the Device Lab allowlist: $Profile"
    }
    if (-not [string]::IsNullOrWhiteSpace($LayoutPath) -and -not [string]::IsNullOrWhiteSpace($PayloadPath)) {
        throw 'Specify only one of -LayoutPath or -PayloadPath'
    }
    if ([string]::IsNullOrWhiteSpace($LayoutPath) -and [string]::IsNullOrWhiteSpace($PayloadPath)) {
        throw 'apply_ui_profile requires -LayoutPath or -PayloadPath'
    }
    $layout = if (-not [string]::IsNullOrWhiteSpace($LayoutPath)) { (Resolve-Path -LiteralPath $LayoutPath -ErrorAction Stop).Path } else { (Resolve-Path -LiteralPath $PayloadPath -ErrorAction Stop).Path }
    $bytes = [IO.File]::ReadAllBytes($layout)
    if ($bytes.Length -gt 524288) { throw 'Layout payload exceeds 512 KiB' }
    $hash = ([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)
    $checksum = ([BitConverter]::ToString($hash)).Replace('-', '').ToUpperInvariant()
    $remoteName = "layout_$NonceValue.json"
    $command = [ordered]@{
        schemaVersion = 1
        nonce = $NonceValue
        action = 'apply_ui_profile'
        allowlist = @('device_lab.v1', 'apply_ui_profile')
        profile = $Profile
        path = "user://device_lab/inbox/$remoteName"
        size = $bytes.Length
        checksum = $checksum
    }
    $hostPayload = Join-Path ([IO.Path]::GetTempPath()) $remoteName
    [IO.File]::WriteAllBytes($hostPayload, $bytes)
    return @{ command = $command; payload = $hostPayload; remoteName = $remoteName }
}

function New-PlayerStateCommand {
    param([string]$NonceValue)
    if ([string]::IsNullOrWhiteSpace($PayloadPath)) { throw 'apply_player_state requires -PayloadPath' }
    $source = [IO.Path]::GetFullPath($PayloadPath)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Player state payload missing: $source" }
    $bytes = [IO.File]::ReadAllBytes($source)
    if ($bytes.Length -gt 4194304) { throw 'Player state payload exceeds 4 MiB' }
    $checksum = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToUpperInvariant()
    $remoteName = "player_state_$NonceValue.json"
    return @{
        command = [ordered]@{
            schemaVersion = 1
            nonce = $NonceValue
            action = 'apply_player_state'
            allowlist = @('device_lab.v1', 'apply_player_state')
            path = "user://device_lab/inbox/$remoteName"
            checksum = $checksum
            size = $bytes.Length
        }
        payload = $source
        remoteName = $remoteName
    }
}

if ($Action -eq 'screenshot') {
    $nonceValue = Get-SafeNonce
    $target = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path (Get-Location) "device_lab_screenshot_$nonceValue.png" } else { [IO.Path]::GetFullPath($OutputPath) }
    $parent = Split-Path -Parent $target
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $remoteScreenshot = "/sdcard/hardcore_device_lab_$nonceValue.png"
    try {
        Invoke-Adb -Arguments @('shell', 'screencap', '-p', $remoteScreenshot) | Out-Null
        Invoke-Adb -Arguments @('pull', $remoteScreenshot, $target) | Out-Null
    } finally {
        try { Invoke-Adb -Arguments @('shell', 'rm', '-f', $remoteScreenshot) | Out-Null } catch { }
    }
    [pscustomobject]@{ ok = $true; action = 'screenshot'; nonce = $nonceValue; path = $target }
    exit 0
}

$nonceValue = Get-SafeNonce
Ensure-DeviceLabDirs

switch ($Action) {
    'apply_ui_profile' {
        $spec = New-ApplyCommand -NonceValue $nonceValue
        try {
            Push-HostFile -LocalPath $spec.payload -RemoteInboxName $spec.remoteName -NonceValue $nonceValue
            Push-Command -Command $spec.command
        } finally {
            if (Test-Path -LiteralPath $spec.payload) { Remove-Item -LiteralPath $spec.payload -Force }
        }
    }
    'apply_player_state' {
        $spec = New-PlayerStateCommand -NonceValue $nonceValue
        Push-HostFile -LocalPath $spec.payload -RemoteInboxName $spec.remoteName -NonceValue $nonceValue
        Push-Command -Command $spec.command
    }
    { $_ -in @('rollback_player_state', 'rollback_ui_profile') } {
        if ($Checkpoint -notmatch '^[A-Za-z0-9_.-]{1,128}$' -or $Checkpoint.Contains('..')) { throw "$Action requires safe -Checkpoint" }
        Push-Command -Command ([ordered]@{
            schemaVersion = 1
            nonce = $nonceValue
            action = $Action
            allowlist = @('device_lab.v1', $Action)
            checkpoint = $Checkpoint
        })
    }
    'push' {
        if ([string]::IsNullOrWhiteSpace($LayoutPath) -and [string]::IsNullOrWhiteSpace($PayloadPath)) { throw 'push requires -LayoutPath or -PayloadPath' }
        $source = if (-not [string]::IsNullOrWhiteSpace($LayoutPath)) { $LayoutPath } else { $PayloadPath }
        $spec = New-ApplyCommand -NonceValue $nonceValue
        try {
            Push-HostFile -LocalPath $spec.payload -RemoteInboxName $spec.remoteName -NonceValue $nonceValue
        } finally {
            if (Test-Path -LiteralPath $spec.payload) { Remove-Item -LiteralPath $spec.payload -Force }
        }
        [pscustomobject]@{ ok = $true; action = 'push'; nonce = $nonceValue; path = "user://device_lab/inbox/$($spec.remoteName)" }
        exit 0
    }
    'pull' {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw 'pull requires -OutputPath' }
        $remoteName = "$DeviceLabPrivateRoot/outbox/result_$nonceValue.json"
        $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
        if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $text = Invoke-RunAsText -Arguments @('cat', $remoteName)
        $result = $text | ConvertFrom-Json
        if ([int]$result.protocolVersion -ne 1 -or [string]$result.nonce -ne $nonceValue) {
            throw 'Device Lab pull identity validation failed'
        }
        $targetPath = [IO.Path]::GetFullPath($OutputPath)
        $hostTemp = "$targetPath.$nonceValue.tmp"
        [IO.File]::WriteAllText($hostTemp, $text, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $hostTemp -Destination $targetPath -Force
        [pscustomobject]@{ ok = $true; action = 'pull'; nonce = $nonceValue; path = $targetPath }
        exit 0
    }
    default {
        $allowAction = $Action
        $command = [ordered]@{
            schemaVersion = 1
            nonce = $nonceValue
            action = $allowAction
            allowlist = @('device_lab.v1', $allowAction)
        }
        Push-Command -Command $command
    }
}

if ($Action -eq 'push') { exit 0 }
$result = Read-Result -NonceValue $nonceValue
$documentActions = @('snapshot', 'export_player_state', 'list_checkpoints')
if ($documentActions -contains $Action -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $targetPath = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $targetPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $document = switch ($Action) {
        'snapshot' { $result.snapshot; break }
        'export_player_state' { $result.document; break }
        'list_checkpoints' { $result.checkpoints; break }
    }
    if ($null -eq $document) { throw "Device Lab $Action result did not include an export document" }
    $targetTemp = "$targetPath.$nonceValue.tmp"
    $json = $document | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($targetTemp, $json, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $targetTemp -Destination $targetPath -Force
    $result | Add-Member -NotePropertyName outputPath -NotePropertyValue $targetPath -Force
}
$result
