using Luna.Core;
using Xunit;

namespace Luna.Core.Tests;

public class CompanionPublicationTests
{
    [Theory]
    [InlineData("write", false)]
    [InlineData("write", true)]
    [InlineData("flush", false)]
    [InlineData("flush", true)]
    [InlineData("durable", false)]
    [InlineData("durable", true)]
    public void FailedPublicationPreservesPriorBytesAndAllowsRegeneration(string failure, bool existing)
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_test.mp4");
            var environment = new RecordingEnvironment(11, 26100, 1920, 1080, 1);
            Prompt.Write(take, environment);
            foreach (var path in new[] { RecordingFiles.MetadataPath(take), Path.ChangeExtension(take, ".prompt.md") })
            {
                var prior = File.ReadAllBytes(path);
                if (!existing) File.Delete(path);
                Assert.Throws<IOException>(() => Prompt.WriteDurable(path, new string('x', 4096), temporary => new RefusingStream(temporary, failure)));
                if (existing) Assert.Equal(prior, File.ReadAllBytes(path));
                else Assert.False(File.Exists(path));
                Assert.Empty(Directory.GetFiles(directory, "*.tmp"));
                if (path == RecordingFiles.MetadataPath(take)) Prompt.Write(take, environment);
            }
            var prompt = Prompt.LoadOrRegenerate(take);
            Assert.Contains("Windows 11 (build 26100) | 1920×1080 @ 1x", prompt);
            Assert.Equal(prompt, File.ReadAllText(Path.ChangeExtension(take, ".prompt.md")));
            Assert.Empty(Directory.GetFiles(directory, "*.tmp"));
        }
        finally { Directory.Delete(directory, true); }
    }

    private sealed class RefusingStream(string path, string failure) : FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None)
    {
        public override void Write(ReadOnlySpan<byte> buffer)
        {
            if (failure == "write") { base.Write(buffer[..1]); throw new IOException("Injected write refusal."); }
            base.Write(buffer);
        }
        public override void Flush()
        {
            if (failure == "flush") throw new IOException("Injected buffered flush refusal.");
            base.Flush();
        }
        public override void Flush(bool flushToDisk)
        {
            if (failure == "durable" && flushToDisk) throw new IOException("Injected durable flush refusal.");
            base.Flush(flushToDisk);
        }
    }
}
