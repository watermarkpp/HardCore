[CmdletBinding()]
param(
    [string]$ApkPath = 'C:\Users\Administrator\Desktop\HardCore-20260905-audit-milestone-debug.apk',
    [ValidatePattern('^[0-9a-fA-F]{40}$')][string]$SourceCommit = '52ae0565856c2d99a28639b2bf0c6278186e0858',
    [switch]$InventoryOnly,
    [switch]$VerifyExisting
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$expectedApkSha256 = '26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664'
$assetPrefix = 'assets/'
$resourcePrefix = 'res://'
$outputDir = [IO.Path]::GetFullPath((Join-Path $root 'outputs/device_lab_base'))
$outputPrefix = '52ae0565_'
$packName = $outputPrefix + 'apk_asset_base.pck'
$reportName = $outputPrefix + 'apk_asset_base.json'
$entriesName = $outputPrefix + 'apk_asset_base.entries.jsonl'
$verifyReportName = $outputPrefix + 'apk_asset_base.verify.json'
$packerScript = Join-Path $root 'tools/hotfix_apk_asset_base_pck.gd'
$godot = Join-Path $root 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
$logDir = Join-Path $root 'outputs/test_logs'
$packLog = Join-Path $logDir 'hotfix_apk_asset_base_pack.log'
$verifyLog = Join-Path $logDir 'hotfix_apk_asset_base_verify.log'
$fixedSourceCommit = '52ae0565856c2d99a28639b2bf0c6278186e0858'

function Assert-HotfixWorkDirectory([string]$Candidate) {
    $baseFull = [IO.Path]::GetFullPath($outputDir).TrimEnd('\')
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    $expectedParent = $baseFull + '\'
    $leaf = Split-Path -Leaf $candidateFull
    if (-not $candidateFull.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase) -or $leaf -notmatch '^52ae0565_work_[0-9a-f]{32}$') {
        throw "unsafe hotfix work directory: $candidateFull"
    }
    if (Test-Path -LiteralPath $baseFull) {
        $baseItem = Get-Item -LiteralPath $baseFull -Force
        $resolvedBase = (Resolve-Path -LiteralPath $baseFull -ErrorAction Stop).Path
        if (-not $baseItem.PSIsContainer -or (($baseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or [IO.Path]::GetFullPath($resolvedBase) -ne $baseFull) {
            throw "hotfix output directory is not a normal directory: $baseFull"
        }
    }
    if (Test-Path -LiteralPath $candidateFull) {
        $resolved = (Resolve-Path -LiteralPath $candidateFull -ErrorAction Stop).Path
        if ([IO.Path]::GetFullPath($resolved) -ne $candidateFull) {
            throw "hotfix work directory resolves outside its requested path: $candidateFull"
        }
        $item = Get-Item -LiteralPath $candidateFull -Force
        if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "hotfix work directory is not a normal directory: $candidateFull"
        }
    }
    return $candidateFull
}

function Assert-NoReparseDescendant([string]$Directory) {
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($Directory)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($childPath in [IO.Directory]::EnumerateFileSystemEntries($current)) {
            $child = Get-Item -LiteralPath $childPath -Force
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "refusing to traverse or delete a reparse point: $childPath"
            }
            if ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            }
        }
    }
}

function Remove-HotfixWorkDirectory([string]$Candidate) {
    $candidateFull = Assert-HotfixWorkDirectory $Candidate
    if (-not (Test-Path -LiteralPath $candidateFull)) {
        return
    }
    Assert-NoReparseDescendant $candidateFull
    Remove-Item -LiteralPath $candidateFull -Recurse -Force
}

function Assert-SafeAssetRelative([string]$RelativePath) {
    if ([string]::IsNullOrEmpty($RelativePath)) {
        throw 'asset path is empty'
    }
    if ($RelativePath.StartsWith('/') -or $RelativePath.StartsWith('\') -or $RelativePath.Contains('\')) {
        throw "asset path is absolute or uses a backslash: $RelativePath"
    }
    if ($RelativePath.Contains(':') -or $RelativePath.Contains([char]0)) {
        throw "asset path contains a drive or NUL: $RelativePath"
    }
    if ($RelativePath.EndsWith('/')) {
        throw "asset path unexpectedly names a directory: $RelativePath"
    }
    foreach ($character in $RelativePath.ToCharArray()) {
        if ([int][char]$character -lt 32) {
            throw "asset path contains a control character: $RelativePath"
        }
    }
    $invalidFileChars = [IO.Path]::GetInvalidFileNameChars()
    foreach ($segment in $RelativePath.Split('/')) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -eq '.' -or $segment -eq '..') {
            throw "asset path contains an unsafe segment: $RelativePath"
        }
        if ($segment.EndsWith(' ') -or $segment.EndsWith('.')) {
            throw "asset path has a Windows-ambiguous segment: $RelativePath"
        }
        foreach ($character in $segment.ToCharArray()) {
            if ($invalidFileChars -contains $character) {
                throw "asset path contains an invalid filename character: $RelativePath"
            }
        }
    }
    if ($RelativePath.Length -gt 4096) {
        throw "asset path is too long: $RelativePath"
    }
}

function Get-ApkAssetInventory([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # The APK stores several non-ASCII asset names without the legacy ZIP
    # UTF-8 flag.  Force UTF-8 on both Windows PowerShell and pwsh so source
    # names are preserved exactly instead of becoming '?' under .NET Framework.
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Read, [Text.Encoding]::UTF8)
    try {
        $rows = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        [long]$totalBytes = 0
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.StartsWith($assetPrefix, [StringComparison]::Ordinal)) {
                continue
            }
            if ($entry.FullName.EndsWith('/')) {
                continue
            }
            $relative = $entry.FullName.Substring($assetPrefix.Length)
            Assert-SafeAssetRelative $relative
            if (-not $seen.Add($relative)) {
                throw "duplicate case-insensitive asset path: $relative"
            }
            $size = [long]$entry.Length
            if ($size -lt 0) {
                throw "negative ZIP entry size: $relative"
            }
            $rows.Add([pscustomobject]@{
                RelativePath = $relative
                ResourcePath = $resourcePrefix + $relative
                ZipLength = $size
            }) | Out-Null
            $totalBytes += $size
        }
        $sorted = @($rows | Sort-Object -Property RelativePath -Culture 'en-US')
        return ,([pscustomobject]@{
            Rows = $sorted
            ResourceCount = $sorted.Count
            ResourceBytes = $totalBytes
            DuplicateCount = 0
            UnsafePathCount = 0
        })
    }
    finally {
        $zip.Dispose()
    }
}

function Copy-ZipEntryWithHash([IO.Compression.ZipArchiveEntry]$Entry, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $input = $null
    $output = $null
    $hash = $null
    try {
        $input = $Entry.Open()
        $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $hash = [Security.Cryptography.SHA256]::Create()
        $buffer = New-Object byte[] (1024 * 1024)
        [long]$bytes = 0
        while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $output.Write($buffer, 0, $read)
            $hash.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
            $bytes += $read
        }
        $hash.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
        $sha256 = ([BitConverter]::ToString($hash.Hash) -replace '-', '').ToUpperInvariant()
        if ($bytes -ne [long]$Entry.Length) {
            throw "ZIP entry byte count changed while extracting: $($Entry.FullName)"
        }
        return [pscustomobject]@{ Bytes = $bytes; Sha256 = $sha256 }
    }
    finally {
        if ($null -ne $hash) { $hash.Dispose() }
        if ($null -ne $output) { $output.Dispose() }
        if ($null -ne $input) { $input.Dispose() }
    }
}

function Get-ZipEntryHash([IO.Compression.ZipArchiveEntry]$Entry) {
    $input = $null
    $hash = $null
    try {
        $input = $Entry.Open()
        $hash = [Security.Cryptography.SHA256]::Create()
        $buffer = New-Object byte[] (1024 * 1024)
        [long]$bytes = 0
        while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $hash.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
            $bytes += $read
        }
        $hash.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
        $sha256 = ([BitConverter]::ToString($hash.Hash) -replace '-', '').ToUpperInvariant()
        if ($bytes -ne [long]$Entry.Length) {
            throw "ZIP entry byte count changed while hashing: $($Entry.FullName)"
        }
        return [pscustomobject]@{ Bytes = $bytes; Sha256 = $sha256 }
    }
    finally {
        if ($null -ne $hash) { $hash.Dispose() }
        if ($null -ne $input) { $input.Dispose() }
    }
}

function Invoke-GodotHelper([string[]]$Arguments, [string]$LogPath, [string]$RuntimeDataDir) {
    if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
        throw "Godot console binary is missing: $godot"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
    New-Item -ItemType Directory -Path $RuntimeDataDir -Force | Out-Null
    $appDataDir = Join-Path $RuntimeDataDir 'appdata'
    $localAppDataDir = Join-Path $RuntimeDataDir 'localappdata'
    New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
    New-Item -ItemType Directory -Path $localAppDataDir -Force | Out-Null
    $oldAppData = $env:APPDATA
    $oldLocalAppData = $env:LOCALAPPDATA
    try {
        $env:APPDATA = $appDataDir
        $env:LOCALAPPDATA = $localAppDataDir
        & $godot @Arguments 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $oldAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue } else { $env:APPDATA = $oldAppData }
        if ($null -eq $oldLocalAppData) { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA = $oldLocalAppData }
    }
    if ($exitCode -ne 0) {
        throw "Godot helper failed with exit code $exitCode; see $LogPath"
    }
}

if ($SourceCommit -ine $fixedSourceCommit) {
    throw "SourceCommit is fixed for this base pack and must equal $fixedSourceCommit"
}
if ($InventoryOnly -and $VerifyExisting) {
    throw 'InventoryOnly and VerifyExisting are mutually exclusive'
}
if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
    throw "APK source does not exist: $ApkPath"
}
$apkFull = [IO.Path]::GetFullPath($ApkPath)
$apkItem = Get-Item -LiteralPath $apkFull
$apkHash = (Get-FileHash -LiteralPath $apkFull -Algorithm SHA256).Hash.ToUpperInvariant()
if ($apkHash -ne $expectedApkSha256) {
    throw "APK SHA-256 mismatch: expected $expectedApkSha256, got $apkHash"
}

$resolvedSource = ((& git -C $root rev-parse --verify "$SourceCommit^{commit}" 2>$null) | Out-String).Trim()
if ($resolvedSource -ne $SourceCommit.ToLowerInvariant()) {
    throw "source commit did not resolve exactly: expected $SourceCommit, got $resolvedSource"
}

$inventory = Get-ApkAssetInventory $apkFull
$rows = @($inventory.Rows)
$pckRows = @($rows | Where-Object { $_.RelativePath.EndsWith('.pck', [StringComparison]::OrdinalIgnoreCase) })
if ($InventoryOnly) {
    [pscustomobject]@{
        ok = $true
        mode = 'inventory'
        apkPath = $apkFull
        apkSha256 = $apkHash
        apkBytes = [long]$apkItem.Length
        sourceCommit = $resolvedSource
        assetPrefix = $assetPrefix
        resourcePrefix = $resourcePrefix
        resourceCount = [int]$inventory.ResourceCount
        resourceBytes = [long]$inventory.ResourceBytes
        duplicatePathCount = [int]$inventory.DuplicateCount
        unsafePathCount = [int]$inventory.UnsafePathCount
        embeddedPckCount = [int]$pckRows.Count
        hasSparsePck = [bool](@($rows | Where-Object { $_.RelativePath -eq 'assets.sparsepck' }).Count -eq 1)
        hasProjectBinary = [bool](@($rows | Where-Object { $_.RelativePath -eq 'project.binary' }).Count -eq 1)
    }
    return
}

if (-not (Test-Path -LiteralPath $packerScript -PathType Leaf)) {
    throw "PCK helper script is missing: $packerScript"
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$packPath = Join-Path $outputDir $packName
$reportPath = Join-Path $outputDir $reportName
$entriesPath = Join-Path $outputDir $entriesName

if ($VerifyExisting) {
    if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) {
        throw "existing base PCK is missing: $packPath"
    }
    $verificationReportPath = Join-Path $outputDir $verifyReportName
    if (Test-Path -LiteralPath $verificationReportPath) {
        throw "refusing to overwrite existing verification report: $verificationReportPath"
    }
    $workDir = Assert-HotfixWorkDirectory (Join-Path $outputDir ('52ae0565_work_' + [Guid]::NewGuid().ToString('N')))
    $manifestPath = Join-Path $workDir 'manifest.tsv'
    $verifyResultPath = Join-Path $workDir 'verify.json'
    $runtimeDataDir = Join-Path $root '.godot/runtime_appdata/hotfix_apk_asset_base_verify'
    $zip = $null
    $manifestWriter = $null
    try {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        $manifestWriter = [IO.StreamWriter]::new($manifestPath, $false, [Text.UTF8Encoding]::new($false))
        $zip = [IO.Compression.ZipFile]::Open($apkFull, [IO.Compression.ZipArchiveMode]::Read, [Text.Encoding]::UTF8)
        foreach ($row in $rows) {
            $entry = $zip.GetEntry($assetPrefix + $row.RelativePath)
            if ($null -eq $entry) {
                throw "ZIP entry disappeared during verification: $($row.RelativePath)"
            }
            $hashed = Get-ZipEntryHash $entry
            $manifestLine = "{0}`t{1}`t{2}`t{3}" -f @($row.ResourcePath, 'verify-only', $hashed.Bytes, $hashed.Sha256)
            $manifestWriter.WriteLine($manifestLine)
        }
        $zip.Dispose()
        $zip = $null
        $manifestWriter.Dispose()
        $manifestWriter = $null
        $verifyArgs = @(
            '--headless', '--path', $root, '--user-data-dir', $runtimeDataDir,
            '--log-file', $verifyLog, '--script', $packerScript, '--',
            '--mode=verify', "--manifest=$manifestPath", "--pack=$packPath",
            "--result=$verifyResultPath", '--sentinel=res://assets.sparsepck'
        )
        Invoke-GodotHelper $verifyArgs $verifyLog $runtimeDataDir
        if (-not (Test-Path -LiteralPath $verifyResultPath -PathType Leaf)) {
            throw "PCK verification completed without a result: $verifyResultPath"
        }
        $verification = Get-Content -LiteralPath $verifyResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [bool]$verification.ok -or [int]$verification.resourceCount -ne [int]$inventory.ResourceCount -or [long]$verification.resourceBytes -ne [long]$inventory.ResourceBytes) {
            throw "PCK verification did not cover the APK inventory: $($verification | ConvertTo-Json -Compress)"
        }
        $packItem = Get-Item -LiteralPath $packPath
        $packHash = (Get-FileHash -LiteralPath $packPath -Algorithm SHA256).Hash.ToUpperInvariant()
        $verificationReport = [ordered]@{
            schemaVersion = 1
            kind = 'apk_assets_pck_base_verification'
            generatedAtUtc = [DateTime]::UtcNow.ToString('o')
            sourceCommit = $resolvedSource
            apk = [ordered]@{ path = $apkFull; bytes = [long]$apkItem.Length; sha256 = $apkHash }
            pack = [ordered]@{ path = $packPath; bytes = [long]$packItem.Length; sha256 = $packHash }
            mapping = [ordered]@{ apkAssetPrefix = $assetPrefix; pckResourcePrefix = $resourcePrefix; resourceCount = [int]$inventory.ResourceCount; resourceBytes = [long]$inventory.ResourceBytes }
            verification = $verification
            verificationMethod = 'Independent fresh headless Godot process loads the existing PCK with replace=true; FileAccess streams every res:// entry. Expected hashes are recomputed directly from the APK ZIP in this VerifyExisting run.'
            helperRevision = 'nul_safe_utf8_buffer_check'
        }
        [IO.File]::WriteAllText($verificationReportPath, ($verificationReport | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        [pscustomobject]@{ ok = $true; mode = 'verify-existing'; pck = $packPath; verificationReport = $verificationReportPath; pckBytes = [long]$packItem.Length; pckSha256 = $packHash; resourceCount = [int]$verification.resourceCount; resourceBytes = [long]$verification.resourceBytes; apkSha256 = $apkHash; sourceCommit = $resolvedSource }
    }
    finally {
        if ($null -ne $zip) { $zip.Dispose() }
        if ($null -ne $manifestWriter) { $manifestWriter.Dispose() }
        Remove-HotfixWorkDirectory $workDir
    }
    return
}

foreach ($path in @($packPath, $reportPath, $entriesPath)) {
    if (Test-Path -LiteralPath $path) {
        throw "refusing to overwrite existing generated output: $path"
    }
}

$workDir = Assert-HotfixWorkDirectory (Join-Path $outputDir ('52ae0565_work_' + [Guid]::NewGuid().ToString('N')))
$payloadDir = Join-Path $workDir 'payload'
$manifestPath = Join-Path $workDir 'manifest.tsv'
$entriesTempPath = Join-Path $workDir 'entries.jsonl'
$tempPackPath = Join-Path $workDir $packName
$verifyResultPath = Join-Path $workDir 'verify.json'
$runtimeDataDir = Join-Path $root '.godot/runtime_appdata/hotfix_apk_asset_base'
$zip = $null
$manifestWriter = $null
$entriesWriter = $null
$completed = $false
try {
    New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
    $manifestWriter = [IO.StreamWriter]::new($manifestPath, $false, [Text.UTF8Encoding]::new($false))
    $entriesWriter = [IO.StreamWriter]::new($entriesTempPath, $false, [Text.UTF8Encoding]::new($false))
    $zip = [IO.Compression.ZipFile]::Open($apkFull, [IO.Compression.ZipArchiveMode]::Read, [Text.Encoding]::UTF8)
    foreach ($row in $rows) {
        $entry = $zip.GetEntry($assetPrefix + $row.RelativePath)
        if ($null -eq $entry) {
            throw "ZIP entry disappeared during extraction: $($row.RelativePath)"
        }
        $destination = Join-Path $payloadDir ($row.RelativePath -replace '/', '\')
        $copied = Copy-ZipEntryWithHash $entry $destination
        $manifestLine = "{0}`t{1}`t{2}`t{3}" -f @($row.ResourcePath, $destination, $copied.Bytes, $copied.Sha256)
        $manifestWriter.WriteLine($manifestLine)
        $entryObject = [ordered]@{
            resourcePath = $row.ResourcePath
            apkAssetPath = $assetPrefix + $row.RelativePath
            bytes = [long]$copied.Bytes
            sha256 = $copied.Sha256
        }
        $entriesWriter.WriteLine(($entryObject | ConvertTo-Json -Compress))
    }
    $zip.Dispose()
    $zip = $null
    $manifestWriter.Dispose()
    $manifestWriter = $null
    $entriesWriter.Dispose()
    $entriesWriter = $null

    $packArgs = @(
        '--headless', '--path', $root, '--user-data-dir', $runtimeDataDir,
        '--log-file', $packLog, '--script', $packerScript, '--',
        '--mode=pack', "--manifest=$manifestPath", "--pack=$tempPackPath"
    )
    Invoke-GodotHelper $packArgs $packLog $runtimeDataDir
    if (-not (Test-Path -LiteralPath $tempPackPath -PathType Leaf)) {
        throw "PCK helper completed without producing a pack: $tempPackPath"
    }

    $verifyArgs = @(
        '--headless', '--path', $root, '--user-data-dir', $runtimeDataDir,
        '--log-file', $verifyLog, '--script', $packerScript, '--',
        '--mode=verify', "--manifest=$manifestPath", "--pack=$tempPackPath",
        "--result=$verifyResultPath", '--sentinel=res://assets.sparsepck'
    )
    Invoke-GodotHelper $verifyArgs $verifyLog $runtimeDataDir
    if (-not (Test-Path -LiteralPath $verifyResultPath -PathType Leaf)) {
        throw "PCK verification completed without a result: $verifyResultPath"
    }
    $verification = Get-Content -LiteralPath $verifyResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [bool]$verification.ok -or [int]$verification.resourceCount -ne [int]$inventory.ResourceCount -or [long]$verification.resourceBytes -ne [long]$inventory.ResourceBytes) {
        throw "PCK verification did not cover the APK inventory: $($verification | ConvertTo-Json -Compress)"
    }

    $packItem = Get-Item -LiteralPath $tempPackPath
    $packHash = (Get-FileHash -LiteralPath $tempPackPath -Algorithm SHA256).Hash.ToUpperInvariant()
    Move-Item -LiteralPath $tempPackPath -Destination $packPath
    Copy-Item -LiteralPath $entriesTempPath -Destination $entriesPath
    $report = [ordered]@{
        schemaVersion = 1
        kind = 'apk_assets_pck_base'
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceCommit = $resolvedSource
        apk = [ordered]@{ path = $apkFull; bytes = [long]$apkItem.Length; sha256 = $apkHash }
        mapping = [ordered]@{ apkAssetPrefix = $assetPrefix; pckResourcePrefix = $resourcePrefix; rule = 'strip exactly one leading APK assets/ prefix'; resourceCount = [int]$inventory.ResourceCount; resourceBytes = [long]$inventory.ResourceBytes }
        pack = [ordered]@{ path = $packPath; bytes = [long]$packItem.Length; sha256 = $packHash }
        verification = $verification
        resourceManifest = $entriesPath
        verificationMethod = 'Fresh headless Godot process loads the PCK with replace=true, then FileAccess streams every res:// entry and compares byte count and SHA-256 to hashes computed directly while reading the APK ZIP.'
        runtimeNote = 'This PCK is a build-time BasePack. It is not an installable runtime patch; the 64 MiB DeviceLab patch limit must not be applied to this input pack.'
        remapClassCacheNote = 'APK .gd.remap, .gdc, .godot/imported, and global_script_class_cache.cfg entries are retained byte-for-byte; no remap or class-cache rewriting is performed.'
    }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $completed = $true
    [pscustomobject]@{ ok = $true; mode = 'build'; pck = $packPath; report = $reportPath; entries = $entriesPath; pckBytes = [long]$packItem.Length; pckSha256 = $packHash; resourceCount = [int]$inventory.ResourceCount; resourceBytes = [long]$inventory.ResourceBytes; apkSha256 = $apkHash; sourceCommit = $resolvedSource }
}
finally {
    if ($null -ne $zip) { $zip.Dispose() }
    if ($null -ne $manifestWriter) { $manifestWriter.Dispose() }
    if ($null -ne $entriesWriter) { $entriesWriter.Dispose() }
    Remove-HotfixWorkDirectory $workDir
}
