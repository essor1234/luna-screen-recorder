# Luna for Windows

Windows implementation of [issue #1](https://github.com/nimitbhargava/luna-screen-recorder/issues/1). The macOS application is unchanged.

## Build and test

Install the .NET 10 SDK. From the repository root:

```sh
dotnet test windows/tests/Luna.Core.Tests
dotnet build windows/src/Luna.App -c Release
```

The Core project contains no Windows APIs and its tests run on Linux and macOS. The WPF app needs Windows 11 (Windows 10 build 19041 is the minimum).

The exe icon is generated from `assets/luna_mascot.png`. Regenerate it on Windows with `powershell -File windows/generate-icon.ps1`; do not edit the ICO by hand.

## Package

On Windows with Visual Studio C++ build tools available:

```powershell
./windows/package.ps1
```

The script publishes a self-contained x64 application, copies the app-local Visual C++ runtime DLLs required by ScreenRecorderLib, and creates `Luna-Windows-x64.zip`. Do not distribute a publish folder without these DLLs. The Actions workflow runs portable tests on all three platforms and uploads the Windows zip.

The executable is unsigned. Windows SmartScreen may show a warning: inspect the source and artifact, then choose **More info**, **Run anyway** if you trust the build. Windows N editions require the Media Feature Pack.

## Quick Windows MVP

Unzip the complete `Luna-Windows-x64.zip` into a writable folder and run `Luna.exe`. No .NET installation or administrator rights are required. Keep all bundled DLLs beside the executable. Luna opens a first-run guide, then lives in the tray and floating bar. Recordings and context files are saved under the Videos known folder in `ScreenRecordings`; settings are in `%APPDATA%\Luna\settings.json`.

- Ctrl+Alt+1: drag an area; click records that monitor; Esc cancels.
- Ctrl+Alt+2: select a window or screen, then Record. Windows have a live preview.
- Ctrl+Alt+3: record the monitor under the cursor.
- Ctrl+Alt+P: pause/resume; Ctrl+Alt+S: stop and save.
- Ctrl+Alt+F: toggle the floating bar; Ctrl+Alt+R: Library.

The floating bar and tray expose system audio and microphone choices. With neither audio source enabled, the MP4 still contains a silent AAC track. Stop writes the MP4, `.prompt.md`, and original `.environment.json` context. Auto-copy puts the prompt text on the clipboard; disabling it leaves the clipboard unchanged. The Library supports paused playback, scrubbing/volume, batch copy, Explorer, Recycle Bin deletion and automatic retention. Existing prompts can be copied for legacy clips; missing prompts require original environment metadata and never invent recording context.

This quick version uses pinned ScreenRecorderLib7.0.1 with H.264 High at30fps, faststart, and unconstrained VBR. The issue's bitrate formula configures average bitrate, not a strict cap. Keyframes use the encoder default; a one-second interval is not guaranteed. The user accepted lower recording quality to get a working Windows version now. These deviations remain visible for later issue acceptance; no upstream extension is required to run this build.

The Library currently shows file/date/size rows rather than per-clip thumbnail and duration badges; its Fullscreen button maximizes the Library. Mixed-DPI geometry, all audio combinations/privacy settings, Windows N, Gemini upload and clean Windows Sandbox need the manual checks below. Local synthetic own-window capture is evidence for actual video/stop/clipboard behavior, not proof of every real-monitor acceptance item. The app makes no network calls.

## Before opening a pull request

Use one feature branch and one PR for issue #1, with `Closes #1` in its description. Keep scaffold/CI, recording/stop flow and Library/settings changes in separate tested milestone commits. Stage only the allowed Windows paths; do not normalize unrelated macOS line endings. Fork and push only after reviewing the complete diff and local validation. The PR must include real-machine details, the acceptance checklist with honest missing items, screenshots, a demo recorded by Luna for Windows itself under 10 MB, and ffprobe evidence per capture mode. Record the AI agent/model used as the issue requests, without adding an AI commit coauthor.

## Native acceptance checklist

- Unzip the actual self-contained CI artifact in Windows Sandbox with no .NET or VC++ redistributable installed; confirm normal startup without elevation or missing DLLs.
- Check first-run Welcome, dismissed Welcome returning next launch, single-instance Library activation, hotkey conflicts, persistent/corrupt settings recovery and dynamic retention labels.
- Test area, picked-window and cursor-monitor capture at 150% and mixed-monitor scales, including negative monitor coordinates. Confirm all Luna UI is excluded, clicks are highlighted, and window closure/display removal saves existing video.
- Verify pause removes five seconds and timer pauses; finalization, plain-text clipboard and toast finish within two seconds. Test auto-copy disabled with clipboard unchanged.
- For all four audio combinations, verify exactly one AAC 48 kHz stereo track; both sources must be audible and no-sources must be silent. Check microphone privacy denial and device fallback.
- Inspect H.264 High, 30 fps, even logical dimensions, keyframe interval, constrained bitrate/file size and moov-before-mdat with ffprobe/atom inspection. Upload to Gemini in Chrome without a format error.
- Exercise Library player/scrubber, batch text/file copy, Explorer, empty state and deletion immediately after playback. Confirm media and sidecars go to the Recycle Bin.
- Backdate an owned take by eight days with retention seven; confirm it and sidecars are removed on next launch while an unrelated `notes.mp4` and open/in-progress takes remain.
- Capture final UI screenshots and a synthetic-content demo. Record Windows build, CPU architecture, monitors and scale percentages. Do not mark an unexecuted check as passed.
