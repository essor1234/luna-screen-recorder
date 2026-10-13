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

## Current development status

This is an early development milestone, not a completed Windows recorder. It supplies the portable contracts and behavioral tests, WPF project, app-local packaging workflow, and initial shell, Library, Settings and Welcome screens. ScreenRecorderLib 7.0.1 loads on .NET 10, but does not expose the maximum VBR bitrate or keyframe interval required by issue #1. The selected approach is an upstream 7.x extension followed by an exact released-package pin. Recording integration and capture acceptance await owner confirmation and that compatible release.

Current Library work includes paused playback, seeking/volume, multiple selection, text/file clipboard formats, Explorer, Recycle Bin deletion and file watching. The final thumbnail/duration presentation, player fullscreen, contextual actions, recording picker, area overlay and floating controls still need completion with recording integration. The Record buttons in this development build cannot begin a take. Do not submit this milestone as the finished acceptance checklist.

Prompt regeneration uses each clip's owned `.environment.json` sidecar to preserve the original Windows build, logical monitor size and scale. Recording integration must write this metadata with the prompt when a take stops. Imported or older clips without that metadata can still copy an existing prompt, but if their prompt is missing, Luna reports that the original recording environment is unavailable instead of inventing it.

Core tests and a WPF cross-build have been exercised using .NET 10.0.401 on Linux; native .NET 10.0.12 dependency and synthetic UI smoke checks also passed. Native SDK build, macOS tests, real captures, clean Windows Sandbox, GitHub CI, screenshots of the final recorder and a self-recorded demo remain required before submission.

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
