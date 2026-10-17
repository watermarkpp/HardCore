<#
.SYNOPSIS
  Build the pinned Godot 4.7 engine for the HardCore v115 simulation lane.

The default action is a read-only preflight. Native compilation is opt-in via
-Build and must be run only after the controller freezes the engine source.
No source patching is performed by this script.
#>
[CmdletBinding()]
param(
    [string]$EngineSource = 'C:\Users\Administrator\Documents\HardCore-engine-v115\godot',
    [string]$ProjectRoot = '',
    [string]$AndroidRoot = '',
    [string]$OutputRoot = '',
    [string]$ExpectedEngineCommit = '5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88',
    [string]$SourceManifest = '',
    [string]$ExpectedSourceSha256 = '',
    [string]$ExpectedManifestSha256 = '',
    [string]$SourceFreeze = '',
    [switch]$RequireSourceManifest,
    [string]$BundledPython = 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
    [string]$VsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat',
    [string]$JavaHome = '',
    [switch]$Build,
    [switch]$BuildWindowsOnly,
    [switch]$AllowSourceBuild,
    [switch]$Clean,
    [switch]$PrepareModule,
    [string]$ModuleSource = '',
    [string]$ModuleTarget = '',
    [int]$Jobs = 0
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# The former Android branch searched obsolete arm64-only APK names and could
# report PASS without fresh templates. Keep Windows behavior; Android now has
# its explicit two-ABI Native manifest and mandatory APK/AAR byte verification.
if ($Build -and -not $BuildWindowsOnly) {
    throw 'Use tools/build_hardcore_android_templates.py for sealed arm64+x86_64 Android templates; this helper builds Windows with -BuildWindowsOnly.'
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }
if ([string]::IsNullOrWhiteSpace($AndroidRoot)) { $AndroidRoot = 'C:\Users\Administrator\Documents\HardCore\tools\android-build' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $ProjectRoot 'outputs\v115_multicore\build_prep' }
if ([string]::IsNullOrWhiteSpace($SourceManifest)) { $SourceManifest = Join-Path $OutputRoot 'SOURCE_MANIFEST.json' }
if ([string]::IsNullOrWhiteSpace($JavaHome)) { $JavaHome = Join-Path $AndroidRoot 'jdk\jdk-17.0.20+8' }
if ([string]::IsNullOrWhiteSpace($ModuleSource)) { $ModuleSource = Join-Path $ProjectRoot 'native\hardcore_simulation' }
if ([string]::IsNullOrWhiteSpace($ModuleTarget)) { $ModuleTarget = Join-Path $EngineSource 'modules\hardcore_simulation' }
if ([string]::IsNullOrWhiteSpace($SourceFreeze)) { $SourceFreeze = Join-Path $ProjectRoot 'outputs\v115_multicore\physics_exact_rework\SOURCE_FREEZE.json' }
$Build = $Build -or $BuildWindowsOnly
$EngineSource = [IO.Path]::GetFullPath($EngineSource)
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$AndroidRoot = [IO.Path]::GetFullPath($AndroidRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $OutputRoot $stamp
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

function Invoke-Capture([string]$File, [string[]]$ArgumentList, [string]$Name) {
    $o = Join-Path $runRoot "$Name.stdout.log"; $e = Join-Path $runRoot "$Name.stderr.log"
    # Wait for the invoked process, not Start-Process's Windows descendant job.
    # A console host can outlive an exited compiler and keep -Wait stuck.
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $File
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ([IO.Path]::GetFileName($File) -ieq 'cmd.exe') {
        # cmd parses /c itself; CRT backslash escaping of embedded quotes
        # would turn the quoted VsDevCmd path into a different command.
        if ($ArgumentList.Count -ne 3 -or $ArgumentList[0] -ne '/d' -or $ArgumentList[1] -ne '/c') { throw 'Unexpected cmd capture contract.' }
        $info.Arguments = '/d /c ' + $ArgumentList[2]
    } else {
        foreach ($argument in $ArgumentList) { $info.ArgumentList.Add($argument) }
    }
    $p = [Diagnostics.Process]::new()
    $p.StartInfo = $info
    try {
        if (-not $p.Start()) { throw "Cannot start build command: $File" }
        $stdout = $p.StandardOutput.ReadToEndAsync()
        $stderr = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        [IO.File]::WriteAllText($o, $stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText($e, $stderr.GetAwaiter().GetResult())
        return [ordered]@{ command=$File; arguments=$ArgumentList; exit_code=[int]$p.ExitCode; stdout=$o; stderr=$e }
    } finally { $p.Dispose() }
}
function Tool([string]$Name) { $c = Get-Command $Name -ErrorAction SilentlyContinue; if ($null -eq $c) { return $null }; return $c.Source }
function FileFact([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [ordered]@{ path=$Path; exists=$false } }
    $i = Get-Item -LiteralPath $Path; $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return [ordered]@{ path=$Path; exists=$true; bytes=$i.Length; sha256=$h }
}
function DirExists([string]$Path) { return [bool](Test-Path -LiteralPath $Path -PathType Container) }

$git = Tool 'git.exe'; $python = if (Test-Path -LiteralPath $BundledPython -PathType Leaf) { $BundledPython } else { Tool 'python.exe' }
$scons = Join-Path $OutputRoot 'venv\Scripts\scons.exe'
if (-not (Test-Path -LiteralPath $scons -PathType Leaf)) {
    # Artifact directories are separate per source seal, while the pinned
    # dependency runtime can be reused without copying its environment.
    $scons = Join-Path $ProjectRoot 'outputs\v115_multicore\build_prep\venv\Scripts\scons.exe'
    if (-not (Test-Path -LiteralPath $scons -PathType Leaf)) { $scons = $null }
}
$adb = Tool 'adb.exe'; $java = Join-Path $JavaHome 'bin\java.exe'; if (-not (Test-Path -LiteralPath $java -PathType Leaf)) { $java = $null }
$engineHead = ''; $engineDirty = $null; $engineTag = ''
if ((DirExists (Join-Path $EngineSource '.git')) -or (Test-Path (Join-Path $EngineSource '.git'))) {
    $engineHead = ((& $git -C $EngineSource rev-parse HEAD 2>$null) -join '').Trim()
    $engineDirty = (@(& $git -C $EngineSource status --porcelain) | Measure-Object).Count
    $engineTag = ((& $git -C $EngineSource describe --tags --exact-match HEAD 2>$null) -join '').Trim()
}
$projectHead = ((& $git -C $ProjectRoot rev-parse HEAD 2>$null) -join '').Trim()
$projectStatus = @(& $git -C $ProjectRoot status --porcelain --untracked-files=normal)
$fingerprintFiles = @('project.godot','export_presets.cfg','tools/build_hardcore_simulation_engine.ps1','tools/build_android_isolated.ps1')
$sourceFacts = [ordered]@{}
foreach ($rel in $fingerprintFiles) { $sourceFacts[$rel] = FileFact (Join-Path $ProjectRoot $rel) }
$manifestExists = Test-Path -LiteralPath $SourceManifest -PathType Leaf
$manifest = $null
if ($manifestExists) { $manifest = Get-Content -Raw -LiteralPath $SourceManifest | ConvertFrom-Json }
$manifestValid = $false
if ($manifestExists) {
    $manifestValid = ($manifest.schema -eq 'hardcore.v115.source_manifest.v1' -and
        $manifest.project_head -eq $projectHead -and $manifest.engine_commit -eq $ExpectedEngineCommit -and
        -not [string]::IsNullOrWhiteSpace([string]$manifest.source_sha256) -and
        $manifest.changed_files -and $manifest.module_inputs -and $manifest.build_config -and
        ([string]$manifest.build_config.precision -eq 'single') -and
        ([string]$manifest.build_config.windows_arch -eq 'x86_64') -and
        (@($manifest.build_config.android_abis) -contains 'arm64-v8a'))
    if ($manifestValid -and -not [string]::IsNullOrWhiteSpace($ExpectedSourceSha256)) { $manifestValid = ([string]$manifest.source_sha256).ToLowerInvariant() -eq $ExpectedSourceSha256.ToLowerInvariant() }
}
$manifestSha = if ($manifestExists) { (Get-FileHash -LiteralPath $SourceManifest -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }

$jdk = Get-ChildItem (Join-Path $AndroidRoot 'jdk') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$sdk = Join-Path $AndroidRoot 'sdk'
$ndk = Get-ChildItem (Join-Path $sdk 'ndk') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
$buildTools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
$abi = @('arm64-v8a','armeabi-v7a','x86_64','x86') | ForEach-Object { [ordered]@{ abi=$_; available=DirExists (Join-Path $sdk "platforms\android-36") } }

$facts = [ordered]@{
    schema='hardcore.v115.engine_build_prep.v1'; generated_at=(Get-Date).ToString('o'); status='PREPARED'
    build_started=$false; build_allowed=($Build -and $AllowSourceBuild); source_patch_default=$false
    project_root=$ProjectRoot; project_head=$projectHead; project_dirty_rows=$projectStatus.Count; project_dirty_sample=@($projectStatus | Select-Object -First 8)
    engine_source=$EngineSource; engine_head=$engineHead; expected_engine_commit=$ExpectedEngineCommit; engine_exact_match=($engineHead -eq $ExpectedEngineCommit); engine_dirty_rows=$engineDirty; engine_tag=$engineTag
    tools=[ordered]@{ git=$git; python=$python; scons=$scons; adb=$adb; java=$java; vsdevcmd=$VsDevCmd; java_home=$JavaHome; sdkmanager=(Join-Path $AndroidRoot 'sdk\cmdline-tools\latest\bin\sdkmanager.bat') }
    android=[ordered]@{ root=$AndroidRoot; sdk_exists=DirExists $sdk; jdk=if($jdk){$jdk.FullName}else{$null}; ndk=if($ndk){$ndk.FullName}else{$null}; build_tools=if($buildTools){$buildTools.FullName}else{$null}; platform_android_36=DirExists (Join-Path $sdk 'platforms\android-36'); abis=$abi }
    signing_baseline=[ordered]@{ package_id='com.personal.mafaoffline'; preserve_existing_signature=$true; secret_values_emitted=$false; source='tools/android_seal/bridge/inject_sources_resign.ps1' }
    source_fingerprint=$sourceFacts
    source_manifest=[ordered]@{ path=$SourceManifest; exists=$manifestExists; valid=$manifestValid; expected_sha256=$ExpectedSourceSha256; expected_manifest_sha256=$ExpectedManifestSha256; manifest_sha256=$manifestSha; source_sha256=if($manifest){$manifest.source_sha256}else{$null} }
    outputs=[ordered]@{ run_root=$runRoot; windows_console=(Join-Path $OutputRoot 'Godot_v115-stable_win64_console.exe'); windows_native=(Join-Path $OutputRoot 'Godot_v115-stable_win64.exe'); android_debug=(Join-Path $OutputRoot 'android_debug'); android_release=(Join-Path $OutputRoot 'android_release'); templates=(Join-Path $OutputRoot 'templates') }
    invocation=[ordered]@{ build=$Build.IsPresent; build_windows_only=$BuildWindowsOnly.IsPresent; allow_source_build=$AllowSourceBuild.IsPresent; clean=$Clean.IsPresent; jobs=$Jobs }
}

if ($PrepareModule) {
    $moduleSourceFull = [IO.Path]::GetFullPath($ModuleSource); $moduleTargetFull = [IO.Path]::GetFullPath($ModuleTarget)
    if (-not (Test-Path -LiteralPath $moduleSourceFull -PathType Container)) { throw "Module source missing: $moduleSourceFull" }
    $engineModulesPrefix = [IO.Path]::GetFullPath((Join-Path $EngineSource 'modules')) + [IO.Path]::DirectorySeparatorChar
    if (-not $moduleTargetFull.StartsWith($engineModulesPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Module target must remain under engine/modules.' }
    $moduleFiles = @(Get-ChildItem -LiteralPath $moduleSourceFull -File -Recurse | Where-Object { $_.Extension -in @('.h','.cpp','.py','') } | Sort-Object FullName)
    if ($moduleFiles.Count -eq 0) { throw 'Frozen module source has no explicit source files.' }
    New-Item -ItemType Directory -Force -Path $moduleTargetFull | Out-Null
    foreach ($moduleFile in $moduleFiles) {
        $relative = $moduleFile.FullName.Substring($moduleSourceFull.Length).TrimStart('\','/')
        $destination = Join-Path $moduleTargetFull $relative
        $destinationParent = Split-Path $destination -Parent
        New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
        Copy-Item -LiteralPath $moduleFile.FullName -Destination $destination -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $moduleTargetFull 'SCsub') -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $moduleTargetFull 'config.py') -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $moduleTargetFull 'register_types.cpp') -PathType Leaf)) { throw 'Frozen module copy is incomplete: SCsub/config.py/register_types.cpp required.' }
    $facts.module_prepare=[ordered]@{ status='PASS'; source=$moduleSourceFull; target=$moduleTargetFull; files=@($moduleFiles | ForEach-Object { $_.FullName }); registration='module target is the sole engine registration root' }
}

if (($Build -or $RequireSourceManifest) -and (-not $manifestValid -or [string]::IsNullOrWhiteSpace($ExpectedManifestSha256) -or $manifestSha -ne $ExpectedManifestSha256.ToLowerInvariant())) { throw "Strict source manifest gate failed: provide a sealed manifest plus its expected byte SHA256." }
if ($Build -and -not $AllowSourceBuild) { throw 'Refusing native compilation: pass -AllowSourceBuild after controller freeze.' }
if ($Build) {
    $facts.build_started = $true
    if (-not $facts.engine_exact_match) { throw 'Engine source is not the pinned commit; build stopped.' }
    if ($engineDirty -gt 0 -and -not $manifestValid) { throw 'Engine source has unsealed dirty files; build stopped.' }
    if ($manifestValid) {
        foreach ($entry in @($manifest.changed_files)) {
            $rootName = [string]$entry.root
            $rel = [string]$entry.relative_path
            $expected = ([string]$entry.sha256).ToLowerInvariant()
            $rootPath = if ($rootName -eq 'engine') { $EngineSource } elseif ($rootName -eq 'project') { $ProjectRoot } else { throw "Manifest changed file root is invalid: $rootName" }
            if ([string]::IsNullOrWhiteSpace($rel) -or $expected -notmatch '^[0-9a-f]{64}$' -or [IO.Path]::IsPathRooted($rel)) { throw 'Source manifest changed_files contains an invalid root, path or SHA256.' }
            $absolute = [IO.Path]::GetFullPath((Join-Path $rootPath ($rel -replace '/', '\')))
            $prefix = [IO.Path]::GetFullPath($rootPath) + [IO.Path]::DirectorySeparatorChar
            if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Manifest path escapes its declared root: $rel" }
            if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Manifest changed file is missing: $rel" }
            $actual = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $expected) { throw "Manifest changed file hash mismatch: $rel" }
        }
        foreach ($input in @($manifest.module_inputs)) {
            $rootName = [string]$input.root; $rel = [string]$input.relative_path; $expected = ([string]$input.sha256).ToLowerInvariant()
            $rootPath = if ($rootName -eq 'engine') { $EngineSource } elseif ($rootName -eq 'project') { $ProjectRoot } else { throw 'Manifest module input root invalid.' }
            $absolute = [IO.Path]::GetFullPath((Join-Path $rootPath ($rel -replace '/', '\')))
            if (-not (Test-Path -LiteralPath $absolute -PathType Leaf) -or (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw "Manifest module input hash mismatch: $rootName/$rel" }
        }
        $declared = @{}; foreach ($entry in @($manifest.changed_files)) { $declared[(('{0}/{1}' -f $entry.root,$entry.relative_path) -replace '\\','/')] = $true }
        $rootNames = @('engine'); $rootPaths = @($EngineSource)
        if (-not $BuildWindowsOnly) { $rootNames += 'project'; $rootPaths += $ProjectRoot }
        for ($rootIndex = 0; $rootIndex -lt $rootNames.Count; $rootIndex++) {
            $rootName = $rootNames[$rootIndex]; $rootPath = $rootPaths[$rootIndex]
            $actualRows = @(& $git -C $rootPath diff --name-only HEAD) + @(& $git -C $rootPath ls-files --others --exclude-standard)
            foreach ($row in $actualRows) {
                $relActual = ([string]$row).Trim() -replace '\\','/'
                if (-not [string]::IsNullOrWhiteSpace($relActual) -and -not $declared.ContainsKey(('{0}/{1}' -f $rootName,$relActual))) { throw "Dirty source is absent from sealed manifest: $rootName/$relActual" }
            }
        }
    }
    if ($null -eq $scons -or $null -eq $python -or -not (Test-Path -LiteralPath $VsDevCmd -PathType Leaf) -or (($null -eq $java) -and -not $BuildWindowsOnly)) { throw 'Pinned SCons/Python/MSVC/JDK unavailable; build stopped before native invocation.' }
    $jobsArg = if ($Jobs -gt 0) { "-j$Jobs" } else { '-j2' }
    $target = Join-Path $OutputRoot 'Godot_v115-stable_win64_console.exe'
    $precision = [string]$manifest.build_config.precision
    $windowsArch = [string]$manifest.build_config.windows_arch
    $androidArch = [string]$manifest.build_config.android_arch
    if ($androidArch -ne 'arm64') { throw "Unsupported Android engine arch in manifest: $androidArch" }
    $sconsArgs = @('-C',$EngineSource,'platform=windows','target=editor',("arch=$windowsArch"),'debug_symbols=no',("precision=$precision"),'production=yes',$jobsArg)
    $vsArgs = @('/d','/c',('set "PYTHONHOME=" && set "PYTHONPATH=" && call "{0}" -arch=x64 -host_arch=x64 && "{1}" {2}' -f $VsDevCmd,$scons,($sconsArgs -join ' ')))
    $run = Invoke-Capture (Join-Path $env:SystemRoot 'System32\cmd.exe') $vsArgs 'scons_windows_console'; $facts.windows_build=$run
    if ($run.exit_code -ne 0) { $facts.status='FAIL'; $facts | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $runRoot 'BUILD_PREP_RECEIPT.json'); throw 'Windows engine build failed.' }
    $windowsBinary = Get-ChildItem (Join-Path $EngineSource 'bin') -File -Filter 'godot.windows.editor*.x86_64.console.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    $windowsNative = Get-ChildItem (Join-Path $EngineSource 'bin') -File -Filter 'godot.windows.editor*.x86_64.exe' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.console.exe' } | Select-Object -First 1
    if ($null -eq $windowsBinary -or $null -eq $windowsNative) { throw 'Windows build completed without both console wrapper and native executable.' }
    Copy-Item -LiteralPath $windowsBinary.FullName -Destination $target -Force
    Copy-Item -LiteralPath $windowsNative.FullName -Destination $facts.outputs.windows_native -Force
    $facts.windows_artifact=FileFact $target; $facts.windows_native_artifact=FileFact $facts.outputs.windows_native
    if ($BuildWindowsOnly) { $facts.status='BUILD_WINDOWS_ONLY_PASS'; $facts.android_build='NOT_RUN' }
    if (-not $BuildWindowsOnly) {
    $androidArgs = @('-C',$EngineSource,'platform=android','target=template_debug',("arch=$androidArch"),("precision=$precision"),'debug_symbols=no','production=yes',$jobsArg)
    $facts.android_debug_build = Invoke-Capture (Join-Path $env:SystemRoot 'System32\cmd.exe') @('/d','/c',('set "JAVA_HOME={0}" && set "ANDROID_HOME={1}" && set "ANDROID_SDK_ROOT={1}" && "{2}" {3}' -f $JavaHome,(Join-Path $AndroidRoot 'sdk'),$scons,($androidArgs -join ' '))) 'scons_android_template_debug'
    if ($facts.android_debug_build.exit_code -ne 0) { $facts.status='FAIL'; $facts | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $runRoot 'BUILD_PREP_RECEIPT.json'); throw 'Android debug template build failed.' }
    $androidReleaseArgs = @('-C',$EngineSource,'platform=android','target=template_release',("arch=$androidArch"),("precision=$precision"),'debug_symbols=no','production=yes',$jobsArg)
    $facts.android_release_build = Invoke-Capture (Join-Path $env:SystemRoot 'System32\cmd.exe') @('/d','/c',('set "JAVA_HOME={0}" && set "ANDROID_HOME={1}" && set "ANDROID_SDK_ROOT={1}" && "{2}" {3}' -f $JavaHome,(Join-Path $AndroidRoot 'sdk'),$scons,($androidReleaseArgs -join ' '))) 'scons_android_template_release'
    if ($facts.android_release_build.exit_code -ne 0) { $facts.status='FAIL'; $facts | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $runRoot 'BUILD_PREP_RECEIPT.json'); throw 'Android release template build failed.' }
    $windowsCandidates = Get-ChildItem (Join-Path $EngineSource 'bin') -File -Filter 'godot.windows.editor.*.console.exe' -ErrorAction SilentlyContinue
    if ($windowsCandidates.Count -gt 0) { Copy-Item -LiteralPath $windowsCandidates[0].FullName -Destination (Join-Path $OutputRoot 'Godot_v115-stable_win64_console.exe') -Force; $facts.windows_artifact=FileFact (Join-Path $OutputRoot 'Godot_v115-stable_win64_console.exe') }
    $templateDir = Join-Path $OutputRoot 'templates'; New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
    $androidCandidates = Get-ChildItem (Join-Path $EngineSource 'bin') -File -Filter 'godot.android.*.arm64.apk' -ErrorAction SilentlyContinue
    foreach ($candidate in $androidCandidates) { $kind = if ($candidate.Name -match 'template_debug') { 'debug' } elseif ($candidate.Name -match 'template_release') { 'release' } else { continue }; $dest = Join-Path $templateDir ("android_{0}.apk" -f $kind); Copy-Item $candidate.FullName $dest -Force; Compress-Archive -Path $dest -DestinationPath (Join-Path $templateDir ("godot-4.7-stable.android.template_{0}.zip" -f $kind)) -Force }
    $facts.template_artifacts = @(Get-ChildItem $templateDir -File -ErrorAction SilentlyContinue | ForEach-Object { FileFact $_.FullName })
    $facts.status='BUILD_WINDOWS_ANDROID_TEMPLATES_PASS'
    }
}
$facts | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $runRoot 'BUILD_PREP_RECEIPT.json')
$facts | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'LATEST_BUILD_PREP.json')
Write-Output ('BUILD_PREP_RECEIPT=' + (Join-Path $runRoot 'BUILD_PREP_RECEIPT.json'))
Write-Output ('ENGINE_EXACT_MATCH=' + $facts.engine_exact_match)
Write-Output ('ENGINE_DIRTY_ROWS=' + $engineDirty)
Write-Output ('ANDROID_ROOT_EXISTS=' + $facts.android.sdk_exists)
Write-Output ('NATIVE_BUILD_STARTED=' + $facts.build_started)
