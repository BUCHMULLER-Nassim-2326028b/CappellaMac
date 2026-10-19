param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$resources = Join-Path (Split-Path $PSScriptRoot -Parent) 'packaging/Resources'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
foreach ($variant in @(@('CappellaLogo.png','AppIcon.ico'), @('CappellaLogo_dark.png','AppIconDark.ico'))) {
    $source = [Drawing.Image]::FromFile((Join-Path $resources $variant[0]))
    $images = @()
    try {
        foreach ($size in @(16,32,48,64,128,256)) {
            $bitmap = [Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            $memory = [IO.MemoryStream]::new()
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $ratio = ($size * 0.9) / [Math]::Max($source.Width,$source.Height)
                $width = [int]($source.Width * $ratio); $height = [int]($source.Height * $ratio)
                $graphics.DrawImage($source,[int](($size-$width)/2),[int](($size-$height)/2),$width,$height)
                $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
                $images += @{ Size=$size; Data=$memory.ToArray() }
            } finally { $memory.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
        }
        $stream = [IO.File]::Create((Join-Path $OutputDirectory $variant[1]))
        $writer = [IO.BinaryWriter]::new($stream)
        try {
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$images.Count)
            $offset = 6 + 16 * $images.Count
            foreach ($image in $images) {
                $edge = if ($image.Size -eq 256) { 0 } else { $image.Size }
                $writer.Write([byte]$edge); $writer.Write([byte]$edge); $writer.Write([uint16]0)
                $writer.Write([uint16]1); $writer.Write([uint16]32)
                $writer.Write([uint32]$image.Data.Length); $writer.Write([uint32]$offset)
                $offset += $image.Data.Length
            }
            foreach ($image in $images) { $writer.Write([byte[]]$image.Data) }
        } finally { $writer.Dispose(); $stream.Dispose() }
    } finally { $source.Dispose() }
}
