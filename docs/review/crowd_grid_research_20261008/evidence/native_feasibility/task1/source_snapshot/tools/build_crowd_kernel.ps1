[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskKernel = Join-Path $taskRoot 'research/native/crowd_kernel'
$taskSdk = Join-Path $taskRoot 'outputs/native_kernel_sdk/godot-cpp'
$taskVenv = Join-Path $taskRoot 'outputs/native_kernel_sdk/venv'
$taskSdkCommit = '272e7f4a5fde342ea20983371fffafdccea07f20'
$taskActualCommit = (& git -C $taskSdk rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $taskActualCommit -ne $taskSdkCommit) { throw 'Pinned godot-cpp commit mismatch; no build performed.' }
& git -C $taskSdk diff --exit-code HEAD --
if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK tracked inputs are modified.' }
if (-not (Test-Path -LiteralPath (Join-Path $taskVenv 'Scripts/python.exe'))) {
    & python -m venv $taskVenv
    if ($LASTEXITCODE -ne 0) { throw 'Local build venv creation failed.' }
}
$taskPython = Join-Path $taskVenv 'Scripts/python.exe'
& $taskPython -m pip install --disable-pip-version-check --quiet 'scons==4.11.1'
if ($LASTEXITCODE -ne 0) { throw 'Pinned SCons installation failed.' }
$taskVsDev = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $taskVsDev)) { throw 'Required MSVC x64 environment unavailable.' }
$taskScons = Join-Path $taskVenv 'Scripts/scons.exe'
$taskProfile = Join-Path $taskKernel 'build_profile.json'
$taskCommand = 'set PYTHONHOME=&& set PYTHONPATH=&& call "{0}" -arch=x64 -host_arch=x64 && "{1}" -C "{2}" platform=windows target=template_debug arch=x86_64 api_version=4.7 optimize=speed precision=single build_profile="{3}" -j4' -f $taskVsDev,$taskScons,$taskKernel,$taskProfile
& cmd.exe /d /c $taskCommand
if ($LASTEXITCODE -ne 0) { throw "Native build failed: exit $LASTEXITCODE" }
$taskDll = Join-Path $taskKernel 'bin/crowd_melee_kernel.windows.template_debug.x86_64.dll'
Get-FileHash -LiteralPath $taskDll -Algorithm SHA256