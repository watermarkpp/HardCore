# Capture compare windows: DPI-aware rect lookup, un-minimize if iconic.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinCap {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[WinCap]::SetProcessDPIAware() | Out-Null
$script:found = New-Object System.Collections.ArrayList
$callback = [WinCap+EnumWindowsProc]{
    param($hWnd, $lParam)
    if ([WinCap]::IsWindowVisible($hWnd)) {
        $sb = New-Object System.Text.StringBuilder 256
        [WinCap]::GetWindowText($hWnd, $sb, 256) | Out-Null
        $title = $sb.ToString()
        if ($title -like '*主界面底框候选*') {
            $rect = New-Object WinCap+RECT
            [WinCap]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
            $iconic = [WinCap]::IsIconic($hWnd)
            if ($iconic) {
                [WinCap]::ShowWindow($hWnd, 9) | Out-Null  # SW_RESTORE
                Start-Sleep -Milliseconds 400
                [WinCap]::SetForegroundWindow($hWnd) | Out-Null
                [WinCap]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
            }
            [void]$script:found.Add([pscustomobject]@{
                Title = $title; Handle = $hWnd; Iconic = $iconic
                Left = $rect.Left; Top = $rect.Top
                Width = ($rect.Right - $rect.Left); Height = ($rect.Bottom - $rect.Top)
            })
        }
    }
    return $true
}
[WinCap]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
Write-Output ("found={0}" -f $script:found.Count)
$outDir = 'C:\Users\Administrator\Documents\HardCore\outputs\chassis_design_20260914\screen_captures'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$index = 0
foreach ($window in $script:found) {
    $index++
    if ($window.Width -le 0 -or $window.Height -le 0) { continue }
    $bitmap = New-Object System.Drawing.Bitmap($window.Width, $window.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($window.Left, $window.Top, 0, 0, $bitmap.Size)
    $graphics.Dispose()
    $path = Join-Path $outDir ("window_{0}.png" -f $index)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Write-Output ("saved={0} rect=({1},{2} {3}x{4}) iconic_before={5} title='{6}'" -f $path, $window.Left, $window.Top, $window.Width, $window.Height, $window.Iconic, $window.Title)
}
