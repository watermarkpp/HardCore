param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$GeometryArguments
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Python = 'C:\Users\Administrator\.cache\my_brush_game\ui_geometry_venv\Scripts\python.exe'
$Requirements = Join-Path $PSScriptRoot 'ui_frame_geometry_requirements.txt'
$Script = Join-Path $PSScriptRoot 'ui_frame_geometry_opencv.py'

if (-not (Test-Path -LiteralPath $Python)) {
    $SystemPython = 'C:\Users\Administrator\AppData\Local\Programs\Python\Python312\python.exe'
    & $SystemPython -m venv (Split-Path -Parent (Split-Path -Parent $Python))
    & $Python -m pip install --disable-pip-version-check -r $Requirements
}

Push-Location $ProjectRoot
try {
    & $Python $Script @GeometryArguments
    if ($LASTEXITCODE -ne 0) {
        throw "UI frame geometry analysis failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
