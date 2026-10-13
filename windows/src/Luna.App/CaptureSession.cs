using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Luna.Core;
using ScreenRecorderLib;
using Forms = System.Windows.Forms;
using CaptureMode = Luna.Core.CaptureMode;

namespace Luna.App;

public partial class App
{
    private Recorder? recorder;
    private FileStream? recordingStream;
    private FloatingBar? bar;
    private readonly Stopwatch recordingTime = new();
    private DispatcherTimer? recordingTimer;
    private RecordingEnvironment recordingEnvironment;
    private string? recordingPath;
    private IntPtr targetWindow;
    private bool selecting, finishing, quitAfterStop, hasFirstFrame;
    internal bool IsRecording => recorder != null;
    internal string? ActiveRecording => recordingPath;
    internal bool IsPaused => recorder?.Status == RecorderStatus.Paused;
    internal string RecordingTime => recordingTime.Elapsed.ToString(@"mm\:ss");
    internal event Action? RecordingChanged;

    internal void RequestRecording(CaptureMode mode = CaptureMode.Area)
    {
        if (IsRecording || selecting || quitAfterStop) return;
        selecting = true;
        var hidden = Windows.Cast<Window>().Where(w => w.IsVisible && w is not ToastWindow).ToArray();
        if (mode != CaptureMode.Screen) foreach (var window in hidden) window.Hide();
        try
        {
            var target = mode == CaptureMode.Screen ? CaptureTarget.ScreenUnderCursor() : mode == CaptureMode.Area ? AreaOverlay.Choose() : CapturePicker.Choose();
            if (target != null) StartCapture(target);
        }
        catch (Exception ex) { ShowNotice("Recording failed: " + ex.Message); }
        finally
        {
            selecting = false;
            foreach (var window in hidden) if (window != bar && Windows.Cast<Window>().Contains(window)) window.Show();
            UpdateBar();
        }
    }
    internal void StartCapture(CaptureTarget target)
    {
        if (IsRecording) return;
        Directory.CreateDirectory(Recordings);
        recordingPath = Path.Combine(Recordings, RecordingFiles.NextName(DateTime.Now, name => File.Exists(Path.Combine(Recordings, name))));
        var size = Luna.Core.Encoding.Size(target.Width, target.Height, target.Scale, target.Mode);
        recordingEnvironment = new RecordingEnvironment(Environment.OSVersion.Version.Build >= 22000 ? 11 : 10, Environment.OSVersion.Version.Build,
            (int)(target.Monitor.Bounds.Width / target.Scale), (int)(target.Monitor.Bounds.Height / target.Scale), target.Scale);
        var source = target.Source;
        source.OutputSize = new ScreenSize(size.Width, size.Height);
        var audio = new List<AudioSourceBase>();
        if (Settings.SystemAudio && LoopbackAudioSource.Default is { } output) audio.Add(output);
        if (Settings.Microphone != "none" && !MicrophoneBlocked())
        {
            var devices = Recorder.GetSystemAudioCaptureDevices();
            var microphone = devices.FirstOrDefault(d => d.DeviceName == Settings.Microphone);
            var input = Settings.Microphone == "system_default" || microphone == null ? CaptureAudioSource.Default : new CaptureAudioSource(microphone.DeviceName);
            if (input != null) audio.Add(input);
        }
        var options = new RecorderOptions
        {
            SourceOptions = new SourceOptions { RecordingSources = new List<RecordingSourceBase> { source } },
            OutputOptions = new OutputOptions { RecorderMode = RecorderMode.Video, OutputFrameSize = new ScreenSize(size.Width, size.Height) },
            VideoEncoderOptions = new VideoEncoderOptions
            {
                Framerate = 30,
                IsFixedFramerate = true,
                Bitrate = Luna.Core.Encoding.BitrateCeiling(size),
                Quality = 55,
                IsHardwareEncodingEnabled = true,
                IsMp4FastStartEnabled = true,
                Encoder = new H264VideoEncoder { EncoderProfile = H264Profile.High, BitrateMode = H264BitrateControlMode.UnconstrainedVBR }
            },
            AudioOptions = new AudioOptions { IsAudioEnabled = true, Channels = AudioChannels.Stereo, Bitrate = AudioBitrate.bitrate_128kbps, AudioSources = audio },
            MouseOptions = new MouseOptions { IsMousePointerEnabled = true, IsMouseClicksDetected = target.Mode != CaptureMode.Window, MouseLeftClickDetectionColor = "#36A9E1", MouseRightClickDetectionColor = "#F59E0B", MouseClickDetectionDuration = 300 }
        };
        targetWindow = target.Window;
        recorder = Recorder.CreateRecorder(options);
        var current = recorder; hasFirstFrame = false;
        current.OnFrameRecorded += (_, _) =>
        {
            if (recorder != current || hasFirstFrame) return;
            hasFirstFrame = true;
            Dispatcher.BeginInvoke(new Action(() => { if (recorder != current) return; recordingTime.Reset(); if (!IsPaused && !finishing) recordingTime.Start(); RecordingChanged?.Invoke(); }));
        };
        recorder.OnRecordingComplete += (_, args) => Dispatcher.BeginInvoke(new Action(() => { if (recorder == current) CompleteRecording(args.FilePath, null); }));
        recorder.OnRecordingFailed += (_, args) => Dispatcher.BeginInvoke(new Action(() => { if (recorder == current) CompleteRecording(args.FilePath, args.Error); }));
        recorder.OnStatusChanged += (_, args) => Dispatcher.BeginInvoke(new Action(() =>
        {
            if (recorder != current) return;
            if (args.Status == RecorderStatus.Recording && hasFirstFrame) recordingTime.Start(); else recordingTime.Stop();
            RecordingChanged?.Invoke(); UpdateBar(); RefreshTray();
        }));
        recordingTime.Reset(); finishing = false;
        recordingTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        recordingTimer.Tick += (_, _) => { if (targetWindow != IntPtr.Zero && !Native.IsWindow(targetWindow)) StopRecording(); RecordingChanged?.Invoke(); bar?.UpdateTime(); if (tray != null) tray.Text = "Luna: recording " + RecordingTime; };
        recordingTimer.Start();
        try
        {
            // Own the output handle so an early stop can close and remove an empty take.
            recordingStream = new FileStream(recordingPath, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read);
            recorder.Record(recordingStream);
        }
        catch (Exception ex) { CompleteRecording(recordingPath, ex.Message); }
        RecordingChanged?.Invoke(); UpdateBar(); RefreshTray();
    }
    private bool MicrophoneBlocked()
    {
        const string key = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
        using var userConsent = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(key);
        using var machineConsent = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(key);
        var blocked = string.Equals(userConsent?.GetValue("Value") as string, "Deny", StringComparison.OrdinalIgnoreCase)
            || string.Equals(machineConsent?.GetValue("Value") as string, "Deny", StringComparison.OrdinalIgnoreCase);
        if (blocked) new ToastWindow("Microphone blocked by Windows privacy settings", null, () => Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone") { UseShellExecute = true }), "Fix").Show();
        return blocked;
    }
    internal void StopRecording() { if (recorder == null || finishing) return; finishing = true; recordingTime.Stop(); recorder.Stop(); bar?.Refresh(); }
    internal void PauseRecording()
    {
        if (recorder == null || finishing) return;
        if (IsPaused) { recorder.Resume(); recordingTime.Start(); } else { recorder.Pause(); recordingTime.Stop(); }
        RecordingChanged?.Invoke(); UpdateBar(); RefreshTray();
    }
    private async void CompleteRecording(string? path, string? error)
    {
        if (recorder == null) return;
        recordingTimer?.Stop(); recordingTimer = null; recordingTime.Stop(); targetWindow = IntPtr.Zero;
        var ownedOutput = recordingStream != null;
        var old = recorder; recorder = null; finishing = false;
        try { old.Dispose(); }
        finally { recordingStream?.Dispose(); recordingStream = null; }
        path = string.IsNullOrEmpty(path) ? recordingPath : path;
        recordingPath = null; RecordingChanged?.Invoke(); UpdateBar(); RefreshTray();
        try
        {
            if (path == null || !File.Exists(path) || new FileInfo(path).Length == 0 || !hasFirstFrame)
            {
                var reason = error ?? "Stopped before any video was recorded. Try a longer recording.";
                if (path != null && ownedOutput)
                {
                    try { await RecordingFiles.DiscardUnrecordedAsync(path); }
                    catch (IOException ex) { Log(ex.ToString()); reason += " The unfinished file could not be removed."; }
                }
                ShowNotice("Recording failed: " + reason);
            }
            else
            {
                try { Mp4FastStart.Apply(path); }
                catch (IOException ex) { Log(ex.ToString()); ShowNotice("Recording saved; MP4 index optimization failed: " + ex.Message); }
                var prompt = Prompt.Write(path, recordingEnvironment);
                if (Settings.AutoCopyForLlms) await ClipboardService.Text(prompt);
                var saved = path;
                new ToastWindow(Settings.AutoCopyForLlms ? "Clipboard updated" : "Recording saved", Settings.AutoCopyForLlms ? "Path and context copied (Ctrl+V)" : "Saved to your library", () => OpenLibrary(saved)).Show();
                if (error != null) ShowNotice("Recording ended: " + error + ". Saved what was recorded.");
                if (Settings.AutoDelete) CleanUp();
            }
        }
        catch (Exception ex) { ShowNotice("Recording saved; context or clipboard failed: " + ex.Message); }
        if (quitAfterStop) Shutdown();
    }
    internal void Quit() { if (IsRecording) { quitAfterStop = true; StopRecording(); } else Shutdown(); }
    internal void ToggleBar() { Settings.FloatingBar = !Settings.FloatingBar; Save(); UpdateBar(); }
    private void UpdateBar()
    {
        if (bar == null) { bar = new FloatingBar(this); bar.Closed += (_, _) => bar = null; }
        bar.Refresh(); if (Settings.FloatingBar && !selecting) bar.Show(); else bar.Hide();
    }
    internal void OpenLibrary(string path) { OpenLibrary(); if (library is LibraryWindow window) window.SelectPath(path); }
}

internal sealed record CaptureTarget(RecordingSourceBase Source, CaptureMode Mode, Forms.Screen Monitor, int Width, int Height, double Scale, IntPtr Window)
{
    internal static CaptureTarget ScreenUnderCursor() => Screen(Forms.Screen.FromPoint(Forms.Cursor.Position));
    internal static CaptureTarget Screen(Forms.Screen screen) => new(new DisplayRecordingSource(screen.DeviceName) { RecorderApi = RecorderApi.WindowsGraphicsCapture }, CaptureMode.Screen, screen, screen.Bounds.Width, screen.Bounds.Height, Native.ScaleAt(screen.Bounds.Left, screen.Bounds.Top), IntPtr.Zero);
    internal static CaptureTarget Area(Forms.Screen screen, System.Drawing.Rectangle area) => new(new DisplayRecordingSource(screen.DeviceName) { RecorderApi = RecorderApi.WindowsGraphicsCapture, SourceRect = new ScreenRect(area.Left - screen.Bounds.Left, area.Top - screen.Bounds.Top, area.Width, area.Height) }, CaptureMode.Area, screen, area.Width, area.Height, Native.ScaleAt(screen.Bounds.Left, screen.Bounds.Top), IntPtr.Zero);
    internal static CaptureTarget ForWindow(IntPtr hwnd)
    {
        var rectangle = Native.WindowBounds(hwnd); var screen = Forms.Screen.FromHandle(hwnd);
        return new(new WindowRecordingSource(hwnd), CaptureMode.Window, screen, rectangle.Width, rectangle.Height, Native.ScaleAt(screen.Bounds.Left, screen.Bounds.Top), hwnd);
    }
}
