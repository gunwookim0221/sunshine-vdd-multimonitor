# Sunshine local-takeover watcher
# Runs in the interactive user session and listens for Windows Raw Input.
#
# Safety model:
# - Learn local HID device paths only while VDD is inactive and at least one physical
#   monitor is active.
# - During VDD-only mode, only input from a previously learned local device can trigger.
# - Unknown devices (including remote/virtual input) are logged and ignored.
# - Takeover first disconnects Sunshine by stopping its service, then verifies/restores
#   the existing safe OFF path, and finally starts Sunshine again.
#
# Run via register-local-takeover.ps1 from an elevated PowerShell.

$ErrorActionPreference = "Stop"

$MultiMonitorTool = "C:\SunshineTools\multimonitortool\MultiMonitorTool.exe"
$OffScript = "C:\SunshineScripts\sunshine-remote-off.ps1"
$LogRoot = "C:\SunshineLogs\local-takeover"
$LogFile = Join-Path $LogRoot "local-takeover.log"
$KnownDevicesFile = Join-Path $LogRoot "known-local-devices.json"
$TopologyCsv = Join-Path $LogRoot "topology-current.csv"

$TopologyRefreshMs = 750
$PollIntervalMs = 100
$MovementWindowMs = 1000
$MovementThreshold = 160
$UnknownDeviceLogCooldownSeconds = 60
$HeartbeatMinutes = 30

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Write-Log {
    param([string]$Message)

    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Rotate-LogIfNeeded {
    try {
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 5MB) {
            $archive = Join-Path $LogRoot ("local-takeover-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
            Move-Item -Path $LogFile -Destination $archive -Force
        }
    } catch {}
}

function Get-MonitorRows {
    Remove-Item $TopologyCsv -Force -ErrorAction SilentlyContinue
    & $MultiMonitorTool /scomma $TopologyCsv | Out-Null
    Start-Sleep -Milliseconds 150

    if (-not (Test-Path $TopologyCsv)) {
        throw "MultiMonitorTool did not create topology CSV."
    }

    return Import-Csv $TopologyCsv
}

function Test-IsVddRow {
    param($Row)

    return (
        [string]$Row.Adapter -match 'Virtual Display Driver' -or
        [string]$Row.'Monitor Name' -match 'VDD by MTT' -or
        [string]$Row.'Short Monitor ID' -match '^MTT' -or
        [string]$Row.'Device ID' -match 'MttVDD'
    )
}

function Get-TopologyState {
    $rows = @(Get-MonitorRows)
    $active = @($rows | Where-Object { $_.Active -eq 'Yes' })
    $activeVdd = @($active | Where-Object { Test-IsVddRow $_ })
    $activePhysical = @($active | Where-Object { -not (Test-IsVddRow $_) })

    $summary = @($active | ForEach-Object {
        "name=$($_.Name),short=$($_.'Short Monitor ID'),monitor=$($_.'Monitor Name'),primary=$($_.Primary)"
    }) -join ' ; '

    [pscustomobject]@{
        IsRemoteMode = ($active.Count -eq 1 -and $activeVdd.Count -eq 1)
        IsLearningSafe = ($activeVdd.Count -eq 0 -and $activePhysical.Count -ge 1)
        ActiveCount = $active.Count
        ActiveVddCount = $activeVdd.Count
        ActivePhysicalCount = $activePhysical.Count
        Summary = $summary
    }
}

function Get-SunshineService {
    try {
        $svc = Get-CimInstance Win32_Service -ErrorAction Stop |
            Where-Object {
                $_.Name -match 'Sunshine' -or
                $_.DisplayName -match 'Sunshine' -or
                $_.PathName -match 'sunshine'
            } |
            Select-Object -First 1

        if ($svc) {
            return Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Log "SERVICE_DISCOVERY_ERROR error='$($_.Exception.Message)'"
    }

    return $null
}

function Test-PhysicalRestored {
    try {
        $state = Get-TopologyState
        Write-Log "RECOVERY_VERIFY physicalActiveCount=$($state.ActivePhysicalCount) activeVddCount=$($state.ActiveVddCount) topology='$($state.Summary)'"
        return ($state.ActivePhysicalCount -ge 2)
    } catch {
        Write-Log "RECOVERY_VERIFY_ERROR error='$($_.Exception.Message)'"
        return $false
    }
}

function Save-KnownDevices {
    param([System.Collections.Generic.HashSet[string]]$KnownDevices)

    @($KnownDevices | Sort-Object) |
        ConvertTo-Json |
        Set-Content -Path $KnownDevicesFile -Encoding UTF8
}

function Load-KnownDevices {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path $KnownDevicesFile) {
        try {
            $items = @(Get-Content $KnownDevicesFile -Raw | ConvertFrom-Json)
            foreach ($item in $items) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
                    [void]$set.Add([string]$item)
                }
            }
        } catch {
            Write-Log "KNOWN_DEVICE_LOAD_ERROR error='$($_.Exception.Message)'"
        }
    }

    # PowerShell enumerates IEnumerable return values. An empty HashSet would otherwise
    # produce no pipeline output and become $null on first-run startup.
    return ,$set
}

function Invoke-LocalTakeover {
    param(
        [string]$Reason,
        [string]$Device
    )

    Write-Log "TAKEOVER_TRIGGER reason='$Reason' device='$Device'"

    $service = Get-SunshineService
    $serviceName = if ($service) { $service.Name } else { "" }
    $serviceStopOk = $false
    $offExit = $null
    $recoveryOk = $false

    if ($service) {
        try {
            $service.Refresh()
            Write-Log "SERVICE_BEFORE name='$serviceName' status='$($service.Status)'"

            if ($service.Status -ne 'Stopped') {
                Write-Log "SERVICE_STOP_START name='$serviceName'"
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, (New-TimeSpan -Seconds 20))
            }

            $service.Refresh()
            $serviceStopOk = ($service.Status -eq 'Stopped')
            Write-Log "SERVICE_STOP_RESULT name='$serviceName' stopped=$serviceStopOk status='$($service.Status)'"
        } catch {
            Write-Log "SERVICE_STOP_ERROR name='$serviceName' error='$($_.Exception.Message)'"
        }
    } else {
        Write-Log "SERVICE_NOT_FOUND limitation='cannot explicitly disconnect Sunshine before recovery'"
    }

    Start-Sleep -Milliseconds 750

    # A normal Sunshine stop may already execute the configured Undo command.
    $recoveryOk = Test-PhysicalRestored

    if (-not $recoveryOk) {
        if (Test-Path $OffScript) {
            try {
                Write-Log "OFF_RECOVERY_START script='$OffScript'"
                $p = Start-Process -FilePath "powershell.exe" -ArgumentList @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", ('"{0}"' -f $OffScript)
                ) -Wait -PassThru -WindowStyle Hidden
                $offExit = $p.ExitCode
                Write-Log "OFF_RECOVERY_RESULT exitCode=$offExit"
            } catch {
                Write-Log "OFF_RECOVERY_ERROR error='$($_.Exception.Message)'"
            }
        } else {
            Write-Log "OFF_RECOVERY_MISSING script='$OffScript'"
        }

        Start-Sleep -Milliseconds 750
        $recoveryOk = Test-PhysicalRestored
    } else {
        Write-Log "OFF_RECOVERY_SKIPPED reason='Sunshine stop/Undo already restored physical monitors'"
    }

    if ($service) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            if ($service.Status -ne 'Running') {
                Write-Log "SERVICE_START_START name='$serviceName'"
                Start-Service -Name $serviceName -ErrorAction Stop
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, (New-TimeSpan -Seconds 20))
            }
            $service.Refresh()
            Write-Log "SERVICE_START_RESULT name='$serviceName' status='$($service.Status)'"
        } catch {
            Write-Log "SERVICE_START_ERROR name='$serviceName' error='$($_.Exception.Message)'"
        }
    }

    try {
        $final = Get-TopologyState
        Write-Log "TAKEOVER_FINAL recoveryOk=$recoveryOk serviceStopOk=$serviceStopOk offExit='$offExit' activeCount=$($final.ActiveCount) physicalActiveCount=$($final.ActivePhysicalCount) activeVddCount=$($final.ActiveVddCount) topology='$($final.Summary)'"
    } catch {
        Write-Log "TAKEOVER_FINAL_ERROR recoveryOk=$recoveryOk error='$($_.Exception.Message)'"
    }

    if ($recoveryOk) {
        Write-Log "TAKEOVER_SUCCESS"
    } else {
        Write-Log "TAKEOVER_FAILED limitation='physical monitor recovery was not verified; existing fail-safe leaves VDD available'"
    }
}

Rotate-LogIfNeeded
Write-Log "WATCHER_START pid=$PID user='$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)'"

if (-not (Test-Path $MultiMonitorTool)) {
    Write-Log "FATAL MultiMonitorTool not found: $MultiMonitorTool"
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$rawInputSource = @'
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace SunshineLocalTakeover
{
    public sealed class RawInputEvent
    {
        public string Kind;
        public string Device;
        public bool KeyDown;
        public int VKey;
        public int MouseButtons;
        public int Dx;
        public int Dy;
        public DateTime TimestampUtc;
    }

    public sealed class RawInputWatcher : NativeWindow
    {
        private const int WM_INPUT = 0x00FF;
        private const int WM_QUIT = 0x0012;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const uint RID_INPUT = 0x10000003;
        private const uint RIDI_DEVICENAME = 0x20000007;
        private const uint RIDEV_INPUTSINK = 0x00000100;
        private const uint RIM_TYPEMOUSE = 0;
        private const uint RIM_TYPEKEYBOARD = 1;

        [StructLayout(LayoutKind.Sequential)]
        private struct RAWINPUTDEVICE
        {
            public ushort usUsagePage;
            public ushort usUsage;
            public uint dwFlags;
            public IntPtr hwndTarget;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RAWINPUTHEADER
        {
            public uint dwType;
            public uint dwSize;
            public IntPtr hDevice;
            public IntPtr wParam;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterRawInputDevices(
            [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] RAWINPUTDEVICE[] pRawInputDevices,
            uint uiNumDevices,
            uint cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetRawInputData(
            IntPtr hRawInput,
            uint uiCommand,
            IntPtr pData,
            ref uint pcbSize,
            uint cbSizeHeader);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetRawInputDeviceInfo(
            IntPtr hDevice,
            uint uiCommand,
            StringBuilder pData,
            ref uint pcbSize);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool PostThreadMessage(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);

        private readonly ConcurrentQueue<RawInputEvent> queue = new ConcurrentQueue<RawInputEvent>();
        private readonly ManualResetEvent started = new ManualResetEvent(false);
        private Thread thread;
        private uint threadId;

        public void Start()
        {
            if (thread != null) return;
            thread = new Thread(Run);
            thread.IsBackground = true;
            thread.Name = "SunshineLocalTakeoverRawInput";
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();

            if (!started.WaitOne(5000))
                throw new InvalidOperationException("Raw Input listener did not start.");
        }

        public void Stop()
        {
            if (threadId != 0)
                PostThreadMessage(threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        }

        public RawInputEvent Dequeue()
        {
            RawInputEvent item;
            return queue.TryDequeue(out item) ? item : null;
        }

        private void Run()
        {
            CreateParams cp = new CreateParams();
            cp.Caption = "SunshineLocalTakeoverRawInput";
            cp.Parent = new IntPtr(-3); // HWND_MESSAGE
            CreateHandle(cp);

            RAWINPUTDEVICE[] devices = new RAWINPUTDEVICE[2];

            devices[0].usUsagePage = 0x01;
            devices[0].usUsage = 0x02; // mouse
            devices[0].dwFlags = RIDEV_INPUTSINK;
            devices[0].hwndTarget = Handle;

            devices[1].usUsagePage = 0x01;
            devices[1].usUsage = 0x06; // keyboard
            devices[1].dwFlags = RIDEV_INPUTSINK;
            devices[1].hwndTarget = Handle;

            if (!RegisterRawInputDevices(devices, (uint)devices.Length, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

            threadId = GetCurrentThreadId();
            started.Set();
            Application.Run();
            DestroyHandle();
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_INPUT)
            {
                try { ParseRawInput(m.LParam); }
                catch { }
            }

            base.WndProc(ref m);
        }

        private void ParseRawInput(IntPtr rawHandle)
        {
            uint size = 0;
            uint headerSize = (uint)Marshal.SizeOf(typeof(RAWINPUTHEADER));

            if (GetRawInputData(rawHandle, RID_INPUT, IntPtr.Zero, ref size, headerSize) == 0xFFFFFFFF || size == 0)
                return;

            IntPtr buffer = Marshal.AllocHGlobal((int)size);
            try
            {
                uint read = GetRawInputData(rawHandle, RID_INPUT, buffer, ref size, headerSize);
                if (read == 0xFFFFFFFF || read == 0)
                    return;

                RAWINPUTHEADER header = (RAWINPUTHEADER)Marshal.PtrToStructure(buffer, typeof(RAWINPUTHEADER));
                string device = GetDeviceName(header.hDevice);
                int offset = (int)headerSize;

                if (header.dwType == RIM_TYPEKEYBOARD)
                {
                    int vkey = (ushort)Marshal.ReadInt16(buffer, offset + 6);
                    int message = Marshal.ReadInt32(buffer, offset + 8);
                    bool keyDown = (message == WM_KEYDOWN || message == WM_SYSKEYDOWN);

                    RawInputEvent ev = new RawInputEvent();
                    ev.Kind = "keyboard";
                    ev.Device = device;
                    ev.KeyDown = keyDown;
                    ev.VKey = vkey;
                    ev.TimestampUtc = DateTime.UtcNow;
                    queue.Enqueue(ev);
                }
                else if (header.dwType == RIM_TYPEMOUSE)
                {
                    uint buttons = unchecked((uint)Marshal.ReadInt32(buffer, offset + 4));
                    int buttonFlags = (int)(buttons & 0xFFFF);
                    int dx = Marshal.ReadInt32(buffer, offset + 12);
                    int dy = Marshal.ReadInt32(buffer, offset + 16);

                    RawInputEvent ev = new RawInputEvent();
                    ev.Kind = "mouse";
                    ev.Device = device;
                    ev.MouseButtons = buttonFlags;
                    ev.Dx = dx;
                    ev.Dy = dy;
                    ev.TimestampUtc = DateTime.UtcNow;
                    queue.Enqueue(ev);
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        private string GetDeviceName(IntPtr device)
        {
            if (device == IntPtr.Zero)
                return "";

            uint chars = 0;
            uint rc = GetRawInputDeviceInfo(device, RIDI_DEVICENAME, null, ref chars);
            if (rc == 0xFFFFFFFF || chars == 0)
                return "";

            StringBuilder sb = new StringBuilder((int)chars + 1);
            rc = GetRawInputDeviceInfo(device, RIDI_DEVICENAME, sb, ref chars);
            if (rc == 0xFFFFFFFF)
                return "";

            return sb.ToString();
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $rawInputSource -ReferencedAssemblies @("System.Windows.Forms.dll", "System.Drawing.dll")
} catch {
    Write-Log "FATAL Raw Input helper compilation failed: $($_.Exception.Message)"
    exit 1
}

$knownDevices = Load-KnownDevices
if ($null -eq $knownDevices) {
    # Defensive fallback for first-run/empty-state correctness.
    $knownDevices = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    Write-Log "KNOWN_DEVICE_INIT_FALLBACK reason='loader-returned-null'"
}
$unknownDeviceLastLog = @{}
$movementState = @{}
$watcher = New-Object SunshineLocalTakeover.RawInputWatcher

try {
    $watcher.Start()
    Write-Log "RAW_INPUT_READY knownDevices=$($knownDevices.Count)"

    $lastTopologyRefresh = [datetime]::MinValue
    $lastHeartbeat = Get-Date
    $lastRemoteMode = $null
    $topology = $null
    $takeoverInProgress = $false

    while ($true) {
        $now = Get-Date

        if ($topology -eq $null -or ($now - $lastTopologyRefresh).TotalMilliseconds -ge $TopologyRefreshMs) {
            try {
                $topology = Get-TopologyState
                $lastTopologyRefresh = $now

                if ($lastRemoteMode -eq $null -or $lastRemoteMode -ne $topology.IsRemoteMode) {
                    Write-Log "MODE_CHANGE remote=$($topology.IsRemoteMode) learningSafe=$($topology.IsLearningSafe) activeCount=$($topology.ActiveCount) physicalActiveCount=$($topology.ActivePhysicalCount) activeVddCount=$($topology.ActiveVddCount) topology='$($topology.Summary)'"
                    $lastRemoteMode = $topology.IsRemoteMode
                    $movementState.Clear()
                }
            } catch {
                Write-Log "TOPOLOGY_ERROR error='$($_.Exception.Message)'"
                $topology = $null
            }
        }

        if (($now - $lastHeartbeat).TotalMinutes -ge $HeartbeatMinutes) {
            $remoteValue = if ($topology) { $topology.IsRemoteMode } else { "unknown" }
            Write-Log "HEARTBEAT remote=$remoteValue knownDevices=$($knownDevices.Count)"
            $lastHeartbeat = $now
        }

        $ev = $watcher.Dequeue()
        while ($ev -ne $null) {
            $device = [string]$ev.Device

            if (-not [string]::IsNullOrWhiteSpace($device) -and $topology -and $topology.IsLearningSafe) {
                if ($knownDevices.Add($device)) {
                    Save-KnownDevices -KnownDevices $knownDevices
                    Write-Log "KNOWN_DEVICE_LEARNED kind='$($ev.Kind)' device='$device' total=$($knownDevices.Count)"
                }
            }

            if ($topology -and $topology.IsRemoteMode -and -not $takeoverInProgress) {
                $isKnownLocal = (-not [string]::IsNullOrWhiteSpace($device) -and $knownDevices.Contains($device))

                if (-not $isKnownLocal) {
                    $key = if ([string]::IsNullOrWhiteSpace($device)) { "<no-device>" } else { $device }
                    $last = $unknownDeviceLastLog[$key]
                    if ($last -eq $null -or (($now - $last).TotalSeconds -ge $UnknownDeviceLogCooldownSeconds)) {
                        Write-Log "REMOTE_INPUT_IGNORED reason='unknown-or-injected-device' kind='$($ev.Kind)' device='$key'"
                        $unknownDeviceLastLog[$key] = $now
                    }
                } else {
                    $reason = $null

                    if ($ev.Kind -eq "keyboard" -and $ev.KeyDown) {
                        $reason = "physical-keyboard-keydown-vk-$($ev.VKey)"
                    } elseif ($ev.Kind -eq "mouse" -and $ev.MouseButtons -ne 0) {
                        $reason = "physical-mouse-button-flags-$($ev.MouseButtons)"
                    } elseif ($ev.Kind -eq "mouse" -and ($ev.Dx -ne 0 -or $ev.Dy -ne 0)) {
                        $state = $movementState[$device]
                        if ($state -eq $null -or (($now - $state.Start).TotalMilliseconds -gt $MovementWindowMs)) {
                            $state = [pscustomobject]@{ Start = $now; Distance = 0 }
                        }

                        $state.Distance += [Math]::Abs([int]$ev.Dx) + [Math]::Abs([int]$ev.Dy)
                        $movementState[$device] = $state

                        if ($state.Distance -ge $MovementThreshold) {
                            $reason = "physical-mouse-move-distance-$($state.Distance)-windowMs-$MovementWindowMs"
                            $movementState.Remove($device)
                        }
                    }

                    if ($reason) {
                        $takeoverInProgress = $true
                        try {
                            Invoke-LocalTakeover -Reason $reason -Device $device
                        } catch {
                            Write-Log "TAKEOVER_EXCEPTION error='$($_.Exception.Message)' line='$($_.InvocationInfo.ScriptLineNumber)' stack='$($_.ScriptStackTrace)'"
                        } finally {
                            $takeoverInProgress = $false
                            $topology = $null
                            $lastTopologyRefresh = [datetime]::MinValue
                            $movementState.Clear()
                        }
                    }
                }
            }

            $ev = $watcher.Dequeue()
        }

        Start-Sleep -Milliseconds $PollIntervalMs
    }
} catch {
    Write-Log "WATCHER_FATAL error='$($_.Exception.Message)' line='$($_.InvocationInfo.ScriptLineNumber)' stack='$($_.ScriptStackTrace)'"
    exit 1
} finally {
    try { $watcher.Stop() } catch {}
    Write-Log "WATCHER_STOP"
}
