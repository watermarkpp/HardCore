$ErrorActionPreference = 'Stop'
$editorRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $editorRoot)
$port = 8765
$url = "http://127.0.0.1:$port/tools/bich_terrain_editor/"

try {
    $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $listener) {
        $python = (Get-Command python -ErrorAction Stop).Source
        Start-Process -FilePath $python -ArgumentList @('-m', 'http.server', "$port", '--bind', '127.0.0.1') -WorkingDirectory $projectRoot -WindowStyle Hidden
        $ready = $false
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 150
            try {
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 1
                if ($response.StatusCode -eq 200) { $ready = $true; break }
            } catch {}
        }
        if (-not $ready) { throw 'Local editor service did not start.' }
    }
    Start-Process $url
} catch {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Map editor failed to start.`n$($_.Exception.Message)", 'Map Editor') | Out-Null
    exit 1
}
