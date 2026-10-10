if (-not ('HardCore.WindowsOwnedProcess' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace HardCore {
    public sealed class WindowsOwnedProcess : IDisposable {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO {
            public int cb;
            public string reserved;
            public string desktop;
            public string title;
            public int x;
            public int y;
            public int xSize;
            public int ySize;
            public int xCountChars;
            public int yCountChars;
            public int fillAttribute;
            public int flags;
            public short showWindow;
            public short reserved2;
            public IntPtr reserved2Ptr;
            public IntPtr stdInput;
            public IntPtr stdOutput;
            public IntPtr stdError;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION {
            public IntPtr process;
            public IntPtr thread;
            public int processId;
            public int threadId;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
            public long perProcessUserTimeLimit;
            public long perJobUserTimeLimit;
            public uint limitFlags;
            public UIntPtr minimumWorkingSetSize;
            public UIntPtr maximumWorkingSetSize;
            public uint activeProcessLimit;
            public IntPtr affinity;
            public uint priorityClass;
            public uint schedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS { public ulong readOps, writeOps, otherOps, readBytes, writeBytes, otherBytes; }
        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION {
            public long totalUserTime;
            public long totalKernelTime;
            public long thisPeriodTotalUserTime;
            public long thisPeriodTotalKernelTime;
            public uint totalPageFaultCount;
            public uint totalProcesses;
            public uint activeProcesses;
            public uint totalTerminatedProcesses;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION basic;
            public IO_COUNTERS io;
            public UIntPtr processMemoryLimit;
            public UIntPtr jobMemoryLimit;
            public UIntPtr peakProcessMemoryUsed;
            public UIntPtr peakJobMemoryUsed;
        }
        private const uint CREATE_SUSPENDED = 0x00000004;
        private const uint CREATE_NO_WINDOW = 0x08000000;
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
        private const int JobObjectExtendedLimitInformation = 9;
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(string app, string command, IntPtr processAttrs, IntPtr threadAttrs, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr CreateJobObject(IntPtr attrs, string name);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint length);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length, out uint returned);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool TerminateJobObject(IntPtr job, uint code);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetExitCodeProcess(IntPtr process, out uint code);

        private IntPtr job;
        private IntPtr process;
        private IntPtr thread;
        public int ProcessId { get; private set; }
        public int Id { get { return ProcessId; } }
        public DateTime StartTime { get; private set; }
        public bool OwnershipEstablished { get; private set; }
        public bool HasExited { get { return ProcessExited; } }
        public bool HasActiveProcesses {
            get {
                var size = Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
                var mem = Marshal.AllocHGlobal(size);
                try {
                    uint returned;
                    if (!QueryInformationJobObject(job, 1, mem, (uint)size, out returned)) throw new Win32Exception(Marshal.GetLastWin32Error(), "QueryInformationJobObject failed");
                    return Marshal.PtrToStructure<JOBOBJECT_BASIC_ACCOUNTING_INFORMATION>(mem).activeProcesses > 0;
                } finally { Marshal.FreeHGlobal(mem); }
            }
        }
        public bool ProcessExited { get { uint code; return GetExitCodeProcess(process, out code) && code != 259; } }
        public int ExitCode { get { uint code; return GetExitCodeProcess(process, out code) ? unchecked((int)code) : -1; } }
        private WindowsOwnedProcess() {}

        public static WindowsOwnedProcess Start(string app, string command, string cwd) {
            var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION pi;
            var result = new WindowsOwnedProcess();
            try {
                result.job = CreateJobObject(IntPtr.Zero, null);
                if (result.job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject failed");
                var limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION(); limits.basic.limitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                if (!SetInformationJobObject(result.job, JobObjectExtendedLimitInformation, ref limits, (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)))) throw new Win32Exception(Marshal.GetLastWin32Error(), "SetInformationJobObject failed");
                if (!CreateProcess(app, command, IntPtr.Zero, IntPtr.Zero, false, CREATE_SUSPENDED | CREATE_NO_WINDOW, IntPtr.Zero, cwd, ref si, out pi)) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateProcess failed");
                result.process = pi.process; result.thread = pi.thread; result.ProcessId = pi.processId; result.StartTime = DateTime.Now;
                if (!AssignProcessToJobObject(result.job, result.process)) throw new Win32Exception(Marshal.GetLastWin32Error(), "AssignProcessToJobObject failed");
                result.OwnershipEstablished = true;
                if (ResumeThread(result.thread) == 0xffffffff) throw new Win32Exception(Marshal.GetLastWin32Error(), "ResumeThread failed");
                return result;
            } catch {
                try {
                    if (result.process != IntPtr.Zero) {
                        if (result.OwnershipEstablished && result.job != IntPtr.Zero) {
                            if (!TerminateJobObject(result.job, 1)) throw new Win32Exception(Marshal.GetLastWin32Error(), "TerminateJobObject failed during startup cleanup");
                        } else if (!TerminateProcess(result.process, 1)) {
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "TerminateProcess failed during startup cleanup");
                        }
                    }
                } finally {
                    result.Dispose();
                }
                throw;
            }
        }
        public void Terminate(uint code) {
            if (job != IntPtr.Zero && !TerminateJobObject(job, code)) throw new Win32Exception(Marshal.GetLastWin32Error(), "TerminateJobObject failed");
        }
        public void Refresh() { }
        public bool WaitForExit(int milliseconds) {
            var until = DateTime.UtcNow.AddMilliseconds(milliseconds);
            while (DateTime.UtcNow < until && !ProcessExited) System.Threading.Thread.Sleep(10);
            return ProcessExited;
        }
        public void Dispose() {
            if (thread != IntPtr.Zero) { CloseHandle(thread); thread = IntPtr.Zero; }
            if (process != IntPtr.Zero) { CloseHandle(process); process = IntPtr.Zero; }
            if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; }
        }
    }
}
'@
}

function Start-WindowsOwnedProcess([string]$Application, [string]$CommandLine, [string]$WorkingDirectory) {
    if ($RunnerIsLinux) { throw 'Windows owned process helper cannot run on Linux.' }
    return [HardCore.WindowsOwnedProcess]::Start($Application, $CommandLine, $WorkingDirectory)
}

function Assert-WindowsOwnedPath([string]$Path, [string]$AllowedRoot, [string]$Label, [string]$WorkspaceRoot = '') {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot = $root }
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\', '/')
    if (-not ($root.Equals($workspace, [StringComparison]::OrdinalIgnoreCase) -or $root.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label allowed root escapes workspace: $AllowedRoot"
    }
    if (-not ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label escapes its owned namespace: $Path"
    }
    $rootRelative = $root.Substring($workspace.Length).TrimStart('\', '/')
    $current = $workspace
    foreach ($part in ($rootRelative -split '[\\/]')) {
        if ([string]::IsNullOrEmpty($part) -or $part -eq '.') { continue }
        $current = Join-Path $current $part
        $ancestor = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $ancestor -and (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw "$Label traverses an owned-root reparse point: $current"
        }
    }
    $relative = $full.Substring($root.Length).TrimStart('\', '/')
    $current = $root
    if ($relative -ne '.') {
        foreach ($part in ($relative -split '[\\/]')) {
            if ([string]::IsNullOrEmpty($part) -or $part -eq '.') { continue }
            $current = Join-Path $current $part
            $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
                throw "$Label traverses a reparse point: $current"
            }
        }
    }
}
