using System.Collections.Generic;
using Luna.Core;
using ScreenRecorderLib;
using Xunit;

namespace Luna.App.Tests;

public class EncoderOptionsTests
{
    [Theory]
    [InlineData(CaptureMode.Area, false)]
    [InlineData(CaptureMode.Area, true)]
    [InlineData(CaptureMode.Screen, false)]
    [InlineData(CaptureMode.Screen, true)]
    [InlineData(CaptureMode.Window, false)]
    [InlineData(CaptureMode.Window, true)]
    public void EveryModeKeepsStableEncoderWhenAudioSourcesChange(CaptureMode mode, bool withAudio)
    {
        // Constructing a source does not open a microphone or capture audio.
        var audio = new List<AudioSourceBase>();
        if (withAudio) audio.Add(new ProcessAudioSource(123));
        var source = new DisplayRecordingSource("synthetic-display");
        var options = App.CreateRecorderOptions(source, new VideoSize(640, 360), mode, audio);
        Assert.False(options.VideoEncoderOptions.IsHardwareEncodingEnabled);
        Assert.True(options.VideoEncoderOptions.IsMp4FastStartEnabled);
        Assert.Same(audio, options.AudioOptions.AudioSources);
        Assert.Same(source, Assert.Single(options.SourceOptions.RecordingSources));
        Assert.True(options.AudioOptions.IsAudioEnabled);
        Assert.Equal(AudioChannels.Stereo, options.AudioOptions.Channels);
        Assert.Equal(640, options.OutputOptions.OutputFrameSize.Width);
        Assert.Equal(360, options.OutputOptions.OutputFrameSize.Height);
    }
}
