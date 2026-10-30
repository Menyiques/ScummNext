# Captura la ventana principal de un proceso a PNG (PrintWindow con PW_RENDERFULLCONTENT).
param([int]$ProcessId, [string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCap {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
}
"@
$p = Get-Process -Id $ProcessId
$h = $p.MainWindowHandle
$r = New-Object WinCap+RECT
[void][WinCap]::GetClientRect($h, [ref]$r)
$w = $r.R - $r.L; $hh = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][WinCap]::PrintWindow($h, $hdc, 3)
$g.ReleaseHdc($hdc)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"$w x $hh"
