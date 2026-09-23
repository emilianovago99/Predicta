# Export the repository's vector mark to native launcher/favicon sizes.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'mantenimiento_predictivo'
[xml]$svg = Get-Content -Raw -LiteralPath (Join-Path $appRoot 'assets/brand/predicta.svg')
function Export-Mark([string]$relativePath, [int]$size) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml($svg.svg.rect.fill))
    $scale = $size / 128.0
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, (8 * $scale))
    $pen.StartCap = $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    foreach ($segment in $svg.svg.g.line) {
        $graphics.DrawLine($pen, [single]([double]$segment.x1 * $scale), [single]([double]$segment.y1 * $scale), [single]([double]$segment.x2 * $scale), [single]([double]$segment.y2 * $scale))
    }
    $target = Join-Path $appRoot $relativePath
    $bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
Export-Mark 'web/favicon.png' 32
foreach ($size in @(192, 512)) {
    Export-Mark "web/icons/Icon-$size.png" $size
    Export-Mark "web/icons/Icon-maskable-$size.png" $size
}
foreach ($entry in @{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}.GetEnumerator()) {
    Export-Mark "android/app/src/main/res/mipmap-$($entry.Key)/ic_launcher.png" $entry.Value
}
foreach ($platform in @('ios', 'macos')) {
    $folder = "$platform/Runner/Assets.xcassets/AppIcon.appiconset"
    $contents = Get-Content -Raw -LiteralPath (Join-Path $appRoot "$folder/Contents.json") | ConvertFrom-Json
    foreach ($entry in $contents.images) {
        if ($entry.filename) {
            $pixels = [int]([double]($entry.size -split 'x')[0] * [double]($entry.scale -replace 'x',''))
            Export-Mark "$folder/$($entry.filename)" $pixels
        }
    }
}
Write-Output 'Predicta icons exported for web, Android, iOS and macOS.'
