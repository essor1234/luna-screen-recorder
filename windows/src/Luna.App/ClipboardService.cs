using System;
using System.Collections.Specialized;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
namespace Luna.App;

internal static class ClipboardService
{
    internal static Task Text(string text) => Retry(() => Clipboard.SetText(text, TextDataFormat.UnicodeText));
    internal static Task Files(string[] paths) => Retry(() => { var files = new StringCollection(); files.AddRange(paths); Clipboard.SetFileDropList(files); });
    private static async Task Retry(Action action)
    {
        for (var i = 0; i < 10; i++)
        {
            try { action(); return; } catch (COMException) when (i < 9) { await Task.Delay(50); }
        }
    }
}
