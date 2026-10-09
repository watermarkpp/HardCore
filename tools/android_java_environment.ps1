# Dot-sourcing defines functions only. Environment changes belong to one build.
function Restore-AndroidJavaEnvironment {
    param([Parameter(Mandatory=$true)]$Context)
    $env:TEMP = $Context.PreviousTemp
    $env:TMP = $Context.PreviousTmp
}

function Enter-AndroidJavaEnvironment {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$JavaHome,
        [Parameter(Mandatory=$true)][string]$EvidenceRoot
    )
    # A short, existing, project-owned directory avoids the Windows user Temp
    # AF_UNIX failure. Do not force a nonexistent directory or TCP fallback.
    $tempRoot = Join-Path $ProjectRoot 'outputs\android_java_temp'
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $tempRoot = (Resolve-Path -LiteralPath $tempRoot).Path
    if ($tempRoot.Length -gt 85) { throw 'Android Java temp root is too long for Windows local socket names.' }
    New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
    $context = [pscustomobject]@{ PreviousTemp=$env:TEMP; PreviousTmp=$env:TMP; TempRoot=$tempRoot }
    try {
        $env:TEMP = $tempRoot
        $env:TMP = $tempRoot
        $java = Join-Path $JavaHome 'bin\java.exe'
        $probe = Join-Path $PSScriptRoot 'android_java_loopback_probe.java'
        # Raw streams avoid PowerShell treating harmless JVM stderr as failure.
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $java
        $info.Arguments = '"' + $probe + '"'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $info
        $outPath = Join-Path $EvidenceRoot 'java-loopback.stdout.log'
        $errPath = Join-Path $EvidenceRoot 'java-loopback.stderr.log'
        if ((Test-Path -LiteralPath $outPath) -or (Test-Path -LiteralPath $errPath)) { throw 'Java preflight evidence already exists.' }
        $out = [IO.File]::Open($outPath, [IO.FileMode]::CreateNew)
        $err = [IO.File]::Open($errPath, [IO.FileMode]::CreateNew)
        try {
            if (-not $process.Start()) { throw 'Java preflight could not start.' }
            $outCopy = $process.StandardOutput.BaseStream.CopyToAsync($out)
            $errCopy = $process.StandardError.BaseStream.CopyToAsync($err)
            if (-not $process.WaitForExit(30000)) { $process.Kill(); $process.WaitForExit(); throw 'Java preflight timed out.' }
            [void]$outCopy.GetAwaiter().GetResult()
            [void]$errCopy.GetAwaiter().GetResult()
            $nativeExit = $process.ExitCode
        } finally { $out.Dispose(); $err.Dispose(); $process.Dispose() }
        $passed = $nativeExit -eq 0 -and [IO.File]::ReadAllText($outPath).Contains('ANDROID_JAVA_LOOPBACK_PASS rounds=32')
        [ordered]@{
            status = $(if ($passed) { 'PASS' } else { 'FAIL' })
            native_exit = $nativeExit
            temp_root = $tempRoot
            scope = 'Process-local TEMP/TMP; actual Selector readiness and Pipe byte transfer, 32 rounds'
            java_sha256 = (Get-FileHash -LiteralPath $java -Algorithm SHA256).Hash.ToLowerInvariant()
            probe_sha256 = (Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant()
            helper_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'java-loopback.json') -Encoding utf8
        if (-not $passed) { throw "Android Java loopback preflight failed; see $errPath. No export started." }
        return $context
    } catch {
        Restore-AndroidJavaEnvironment $context
        throw
    }
}
