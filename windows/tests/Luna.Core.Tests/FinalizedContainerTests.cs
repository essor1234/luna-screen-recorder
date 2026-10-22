using System.Buffers.Binary;
using Luna.Core;
using Xunit;

namespace Luna.Core.Tests;

public class FinalizedContainerTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RejectsUnfinishedSinkOutputWithoutChangingBytes(bool emptyIndex)
    {
        byte[] bytes = [.. Box("ftyp", [0, 0, 0, 0]), .. Box("mdat", [1, 2, 3]), .. (emptyIndex ? Box("moov", []) : Array.Empty<byte>())];
        WithFile(bytes, path =>
        {
            Assert.Throws<InvalidDataException>(() => Mp4FastStart.RequireFinalizedContainer(path));
            Assert.Equal(bytes, File.ReadAllBytes(path));
        });
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void AcceptsFinalizedIndexBeforeOrAfterMedia(bool fastStart)
    {
        var prefix = Box("ftyp", [0, 0, 0, 0]); var media = Box("mdat", [1, 2, 3]);
        var index = Box("moov", [.. Box("mvhd", [0]), .. Box("trak", [0])]);
        byte[] bytes = fastStart ? [.. prefix, .. index, .. media] : [.. prefix, .. media, .. index];
        WithFile(bytes, path =>
        {
            Mp4FastStart.RequireFinalizedContainer(path);
            Assert.Equal(bytes, File.ReadAllBytes(path));
        });
    }

    [Fact]
    public void RejectsTruncatedBoxEvenWhenIndexWasWritten()
    {
        byte[] bytes = [.. Box("ftyp", [0]), .. Box("moov", [.. Box("mvhd", [0]), .. Box("trak", [0])]), .. Box("mdat", [1, 2, 3])[..^1]];
        WithFile(bytes, path => Assert.Throws<InvalidDataException>(() => Mp4FastStart.RequireFinalizedContainer(path)));
    }

    private static void WithFile(byte[] bytes, Action<string> action)
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".mp4");
        try { File.WriteAllBytes(path, bytes); action(path); }
        finally { File.Delete(path); }
    }

    private static byte[] Box(string type, byte[] payload)
    {
        var bytes = new byte[payload.Length + 8]; BinaryPrimitives.WriteUInt32BigEndian(bytes, (uint)bytes.Length);
        System.Text.Encoding.ASCII.GetBytes(type).CopyTo(bytes, 4); payload.CopyTo(bytes, 8); return bytes;
    }
}
