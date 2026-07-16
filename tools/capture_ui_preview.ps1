param(
    [ValidateSet('character', 'exit', 'hud', 'skill')]
    [string]$Mode = 'hud',
    [int]$TimeoutSeconds = 20,
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$PreviewScene = 'res://tests/ui_gothic_preview.tscn'
$ValidationScene = 'res://tests/ui_gothic_preview_test.tscn'

function Stop-ProcessTree([int]$ProcessId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Invoke-GodotWithTimeout([string[]]$Arguments, [string]$LogName, [string]$SuccessPattern, [hashtable]$Environment = @{}) {
    $stdout = Join-Path $LogRoot "$LogName.stdout.log"
    $stderr = Join-Path $LogRoot "$LogName.stderr.log"
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    $savedEnvironment = @{}
    foreach ($key in $Environment.Keys) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
    }
    try {
        $process = Start-Process -FilePath $Godot -ArgumentList $Arguments -WorkingDirectory $ProjectRoot `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
		$earlyFailure = $false
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 150
			$currentError = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -Encoding utf8 -ErrorAction SilentlyContinue } else { '' }
			if ($currentError -match 'SCRIPT ERROR:|Parse Error:|Assertion failed:|ERROR:|No loader found for resource') {
				$earlyFailure = $true
				Stop-ProcessTree -ProcessId $process.Id
				break
			}
        }
		if (-not $process.HasExited -and -not $earlyFailure) {
            Stop-ProcessTree -ProcessId $process.Id
            throw "Godot task timed out after ${TimeoutSeconds}s: $LogName; process tree cleaned"
        }
		$process.WaitForExit()
		$process.Refresh()
		$exitCode = $process.ExitCode
        $combined = @(
            Get-Content -LiteralPath $stdout -Encoding utf8 -ErrorAction SilentlyContinue
            Get-Content -LiteralPath $stderr -Encoding utf8 -ErrorAction SilentlyContinue
        ) -join [Environment]::NewLine
        $hasExplicitSuccess = $combined -match $SuccessPattern
        $hasExplicitFailure = $combined -match 'SCRIPT ERROR:|Parse Error:|Assertion failed:|ERROR:|No loader found for resource'
        if ($hasExplicitFailure -or -not $hasExplicitSuccess) {
            throw "Godot task failed: $LogName`n$combined"
        }
        Write-Output $combined
    }
    finally {
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
        }
    }
}

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot executable not found: $Godot"
}
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

Invoke-GodotWithTimeout `
    -Arguments @('--path', '.', '--resolution', '1280x720', '--position', '40,40', $PreviewScene) `
    -LogName "ui_preview_$Mode" `
    -SuccessPattern 'UI_GOTHIC_PREVIEW_CAPTURE_PASS' `
    -Environment @{ UI_PREVIEW_MODE = $Mode; UI_PREVIEW_CAPTURE = '1' }

if (-not $SkipValidation) {
    Invoke-GodotWithTimeout `
        -Arguments @('--headless', '--path', '.', $ValidationScene) `
        -LogName 'ui_preview_validation' `
        -SuccessPattern 'UI_GOTHIC_PREVIEW_TEST_PASS'
}

Write-Output "UI_PREVIEW_TOOL_PASS mode=$Mode"
