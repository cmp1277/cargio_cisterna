# Regenerates launcher assets from the code-native mark in assets/branding/app_icon.svg.
# Requires Windows PowerShell with System.Drawing. Generated assets are committed.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = Split-Path $PSScriptRoot -Parent
function Write-LauncherIcon([string]$OutputPath, [int]$Size) {
  $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#082F49'))
  $graphics.ScaleTransform(($Size / 1024.0), ($Size / 1024.0))
  $drop = New-Object System.Drawing.Drawing2D.GraphicsPath
  $drop.AddBezier(512,160,430,295,270,413,270,564)
  $drop.AddBezier(270,564,270,725,383,842,512,842)
  $drop.AddBezier(512,842,641,842,754,725,754,564)
  $drop.AddBezier(754,564,754,413,594,295,512,160)
  $drop.CloseFigure()
  $brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#21D6D3'))
  $graphics.FillPath($brush, $drop)
  $shine = New-Object System.Drawing.Drawing2D.GraphicsPath
  $shine.AddBezier(382,533,365,617,405,689,458,716)
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 44)
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $graphics.DrawPath($pen, $shine)
  $graphics.Dispose()
  [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($OutputPath)) | Out-Null
  $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bitmap.Dispose()
  $brush.Dispose()
  $drop.Dispose()
  $shine.Dispose()
  $pen.Dispose()
}
$densities = @{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}
foreach ($density in $densities.Keys) {
  Write-LauncherIcon (Join-Path $appRoot "android/app/src/main/res/mipmap-$density/ic_launcher.png") $densities[$density]
}
$iosIcons = Join-Path $appRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$contents = Get-Content -LiteralPath (Join-Path $iosIcons 'Contents.json') -Raw | ConvertFrom-Json
foreach ($icon in $contents.images) {
  if ($icon.filename) {
    $points = [double]::Parse($icon.size.Split('x')[0], [System.Globalization.CultureInfo]::InvariantCulture)
    $scale = [double]::Parse($icon.scale.Replace('x',''), [System.Globalization.CultureInfo]::InvariantCulture)
    Write-LauncherIcon (Join-Path $iosIcons $icon.filename) ([int]($points * $scale))
  }
}
Write-Output 'Iconos Android e iOS generados.'
