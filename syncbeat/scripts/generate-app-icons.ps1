param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets/branding/app_icon.png'
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)

function New-IconBitmap([int]$Size, [int]$ArtworkSize = $Size) {
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $offset = [int](($Size - $ArtworkSize) / 2)
        $rectangle = [System.Drawing.Rectangle]::new($offset, $offset, $ArtworkSize, $ArtworkSize)
        $graphics.DrawImage($sourceImage, $rectangle, 0, 0, $sourceImage.Width, $sourceImage.Height, [System.Drawing.GraphicsUnit]::Pixel)
    } finally {
        $graphics.Dispose()
    }
    return $bitmap
}

try {
    $densities = @(
        @{ Name = 'mdpi'; Size = 48 },
        @{ Name = 'hdpi'; Size = 72 },
        @{ Name = 'xhdpi'; Size = 96 },
        @{ Name = 'xxhdpi'; Size = 144 },
        @{ Name = 'xxxhdpi'; Size = 192 }
    )
    foreach ($density in $densities) {
        $path = Join-Path $projectRoot "android/app/src/main/res/mipmap-$($density.Name)/ic_launcher.png"
        $bitmap = New-IconBitmap -Size $density.Size
        try { $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) }
        finally { $bitmap.Dispose() }
    }

    # Android adaptive foreground: 108dp canvas, 66dp artwork safe zone at 4x.
    $foregroundDirectory = Join-Path $projectRoot 'android/app/src/main/res/drawable-xxxhdpi'
    [void][System.IO.Directory]::CreateDirectory($foregroundDirectory)
    $foreground = New-IconBitmap -Size 432 -ArtworkSize 264
    try { $foreground.Save((Join-Path $foregroundDirectory 'ic_launcher_foreground.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $foreground.Dispose() }

    # Windows ICO with PNG frames, supported by Windows 10/11.
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $frames = [System.Collections.Generic.List[byte[]]]::new()
    foreach ($size in $sizes) {
        $bitmap = New-IconBitmap -Size $size
        $memory = [System.IO.MemoryStream]::new()
        try {
            $bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
            $frames.Add($memory.ToArray())
        } finally {
            $memory.Dispose()
            $bitmap.Dispose()
        }
    }
    $iconPath = Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'
    $writer = [System.IO.BinaryWriter]::new([System.IO.File]::Create($iconPath))
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($index = 0; $index -lt $sizes.Count; $index++) {
            $dimension = if ($sizes[$index] -eq 256) { 0 } else { $sizes[$index] }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frames[$index].Length)
            $writer.Write([uint32]$offset)
            $offset += $frames[$index].Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
    } finally { $writer.Dispose() }
} finally { $sourceImage.Dispose() }

Write-Output 'Android and Windows icons generated from assets/branding/app_icon.png.'
