# Bring the calibrator main game window to the front, enlarged, next to the preview window.
Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinList {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
    public struct RECT { public int L, T, R, B; }
    public static List<IntPtr> Found = new List<IntPtr>();
    public static bool Cb(IntPtr h, IntPtr l) {
        if (IsWindowVisible(h)) Found.Add(h);
        return true;
    }
}
"@
[WinList]::SetProcessDPIAware() | Out-Null
$targets = Get-Process | Where-Object { $_.ProcessName -like 'Godot*' } | Select-Object -ExpandProperty Id
if (-not $targets) { Write-Output 'NO_GODOT_PROCESS'; exit 1 }
$pids = @{}; foreach ($t in $targets) { $pids[[uint32]$t] = $true }
[WinList]::Found.Clear()
[WinList]::EnumWindows([WinList+EnumProc]{ param($h, $l) [WinList]::Cb($h, $l) }, [IntPtr]::Zero) | Out-Null
$main = [IntPtr]::Zero; $preview = [IntPtr]::Zero
foreach ($h in [WinList]::Found) {
    $outPid = [uint32]0
    [WinList]::GetWindowThreadProcessId($h, [ref]$outPid) | Out-Null
    if (-not $pids.ContainsKey($outPid)) { continue }
    $sb = New-Object System.Text.StringBuilder 256
    [WinList]::GetWindowText($h, $sb, 256) | Out-Null
    $title = $sb.ToString()
    if ($title.Length -eq 0) { continue }
    $r = New-Object WinList+RECT
    [WinList]::GetWindowRect($h, [ref]$r) | Out-Null
    Write-Output ("hwnd=0x{0:X} pid={1} rect=({2},{3})-({4},{5}) title={6}" -f $h.ToInt64(), $outPid, $r.L, $r.T, $r.R, $r.B, $title)
    if ($title -like '*校准*') { $main = $h }
    if ($title -like '*候选*') { $preview = $h }
}
if ($main -eq [IntPtr]::Zero) { Write-Output 'MAIN_WINDOW_NOT_FOUND'; exit 1 }
[WinList]::ShowWindow($main, 9) | Out-Null   # SW_RESTORE
[WinList]::MoveWindow($main, 30, 110, 1860, 830, $true) | Out-Null
[WinList]::SetForegroundWindow($main) | Out-Null
Write-Output 'MAIN_MOVED_FRONT'
