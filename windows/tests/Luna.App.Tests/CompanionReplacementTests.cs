using System;
using System.IO;
using Luna.Core;
using Xunit;

namespace Luna.App.Tests;

public class CompanionReplacementTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RefusedReplacementPreservesCompanionAndCanBeRetried(bool metadata)
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_test.mp4");
            var before = new RecordingEnvironment(11, 26100, 1920, 1080, 1);
            var after = new RecordingEnvironment(11, 26200, 2560, 1440, 1.5);
            Prompt.Write(take, before);
            var path = metadata ? RecordingFiles.MetadataPath(take) : Path.ChangeExtension(take, ".prompt.md");
            var prior = File.ReadAllBytes(path);
            using (var locked = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                var failure = Record.Exception(() => Prompt.Write(take, after));
                Assert.True(failure is IOException or UnauthorizedAccessException, failure?.ToString());
                Assert.Equal(prior, File.ReadAllBytes(path));
                Assert.Empty(Directory.GetFiles(directory, "*.tmp"));
            }
            var result = Prompt.Write(take, after);
            Assert.Equal(result, Prompt.LoadOrRegenerate(take));
            File.Delete(Path.ChangeExtension(take, ".prompt.md"));
            Assert.Equal(result, Prompt.LoadOrRegenerate(take));
            Assert.Contains("Windows 11 (build 26200) | 2560×1440 @ 1.5x", result);
            Assert.Empty(Directory.GetFiles(directory, "*.tmp"));
        }
        finally { Directory.Delete(directory, true); }
    }
}
