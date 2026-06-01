<#
    Generates icon.ico for the app/exe: a Claude-coral rounded-square badge with the
    Lucide "folder-plus" mark in cream. Multi-size (256/64/48/32/16) PNG-in-ICO.
    Run:  powershell -Sta -ExecutionPolicy Bypass -File generate-icon.ps1
    (-Sta required: WPF offscreen rendering.)
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$dir   = $PSScriptRoot
$coral = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xD9,0x77,0x57))  # accent — used for the icon stroke
$dark  = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0x26,0x26,0x24))  # card bg — used for the badge fill
$coral.Freeze(); $dark.Freeze()
# Lucide folder-plus (24x24)
$geo = [Windows.Media.Geometry]::Parse('M12 10v6 M9 13h6 M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z')
$geo.Freeze()

function Render-Png([int]$N) {
    $vis = New-Object Windows.Media.DrawingVisual
    $dc  = $vis.RenderOpen()
    $r   = [double]($N * 0.22)
    $dc.DrawRoundedRectangle($dark, $null, (New-Object Windows.Rect 0,0,$N,$N), $r, $r)
    $frac   = 0.56
    $scale  = ($N * $frac) / 24.0
    $offset = ($N - 24 * $scale) / 2.0
    $tg = New-Object Windows.Media.TransformGroup
    $tg.Children.Add((New-Object Windows.Media.ScaleTransform $scale, $scale))
    $tg.Children.Add((New-Object Windows.Media.TranslateTransform $offset, $offset))
    $dc.PushTransform($tg)
    $pen = New-Object Windows.Media.Pen $coral, 2.2
    $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'; $pen.LineJoin = 'Round'
    $dc.DrawGeometry($null, $pen, $geo)
    $dc.Pop(); $dc.Close()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $N, $N, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($vis)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $ms = New-Object IO.MemoryStream
    $enc.Save($ms)
    ,$ms.ToArray()
}

$sizes = 256, 64, 48, 32, 16
$pngs  = foreach ($s in $sizes) { ,(Render-Png $s) }

$ico = Join-Path $dir 'icon.ico'
$fs  = [IO.File]::Create($ico)
$bw  = New-Object IO.BinaryWriter $fs
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$sizes.Count)   # ICONDIR
$dataOffset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $pngs[$i].Length
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim)      # width, height (0 = 256)
    $bw.Write([byte]0); $bw.Write([byte]0)            # colors, reserved
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)       # planes, bitcount
    $bw.Write([UInt32]$len); $bw.Write([UInt32]$dataOffset)
    $dataOffset += $len
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush(); $fs.Close()
Write-Host "Wrote $ico ($((Get-Item $ico).Length) bytes, sizes: $($sizes -join ', '))" -ForegroundColor Green
