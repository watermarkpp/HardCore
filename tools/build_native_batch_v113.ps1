[CmdletBinding()]
param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$kernel = Join-Path $repo 'research/native/crowd_batch_v113'
$sdk = Join-Path $repo 'outputs/native_batch_ab_v113_20261012/sdk/godot-cpp'
$venv = Join-Path $repo 'outputs/native_batch_ab_v113_20261012/sdk/venv'
$logDir = Join-Path $repo 'outputs/native_batch_ab_v113_20261012/sdk/kernel_build'
$sdkCommit = '272e7f4a5fde342ea20983371fffafdccea07f20'
$python = Join-Path $venv 'Scripts/python.exe'
$scons = Join-Path $venv 'Scripts/scons.exe'
$vsDevCmd = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat'

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
if (-not (Test-Path -LiteralPath $sdk)) { throw "Pinned SDK missing: $sdk" }
$actual = (& git -C $sdk rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actual -ne $sdkCommit) { throw "Pinned godot-cpp mismatch: $actual" }
& git -C $sdk diff --exit-code HEAD --
if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK tracked inputs are modified.' }

if (-not (Test-Path -LiteralPath $python)) {
    & (Join-Path $env:SystemRoot 'System32\cmd.exe') /d /c "python -m venv `"$venv`""
    if ($LASTEXITCODE -ne 0) { throw 'Build venv creation failed.' }
}
& $python -m pip install --disable-pip-version-check --quiet 'scons==4.11.1'
if ($LASTEXITCODE -ne 0) { throw 'Pinned SCons installation failed.' }
if (-not (Test-Path -LiteralPath $vsDevCmd)) { throw 'Required MSVC environment unavailable.' }

if ($Clean) {
    & $scons -C $kernel -c
    if ($LASTEXITCODE -ne 0) { throw 'Native skeleton clean failed.' }
}
$profile = Join-Path $kernel 'build_profile.json'
$command = 'set PYTHONHOME=&& set PYTHONPATH=&& call "{0}" -arch=x64 -host_arch=x64 && "{1}" -C "{2}" platform=windows target=template_debug arch=x86_64 api_version=4.7 optimize=speed precision=single build_profile="{3}" -j4' -f $vsDevCmd, $scons, $kernel, $profile
$log = Join-Path $logDir 'build.log'
& cmd.exe /d /c $command 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "Native skeleton build failed: exit $LASTEXITCODE" }
$dll = Join-Path $kernel 'bin/crowd_batch_v113.windows.template_debug.x86_64.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw "Expected DLL missing: $dll" }
$sha = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
[ordered]@{
    status = 'PASS'
    sdk_commit = $actual
    sdk_expected = $sdkCommit
    scons_version = '4.11.1'
    engine_api = '4.7'
    platform = 'windows'
    arch = 'x86_64'
    target = $dll
    sha256 = $sha
    log = $log
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logDir 'build_receipt.json') -Encoding UTF8
Get-Content -Raw (Join-Path $logDir 'build_receipt.json')
