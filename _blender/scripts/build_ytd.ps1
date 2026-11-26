# Bygger den fælles texture dictionary stream/m1_cf_tex.ytd ud fra _blender/ycd/m1_cf_tex.json
# (skrevet af export_all() i cfbuild.py: {teksturnavn: dds-fil i _blender/tex}).
#   powershell -File build_ytd.ps1 [-CodeWalker <mappe med CodeWalker.Core.dll>]
param(
    [string]$CodeWalker = "$env:USERPROFILE\Desktop\CodeWalker30_dev46\CodeWalker30_dev46"
)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[void][Reflection.Assembly]::LoadFrom((Join-Path $CodeWalker 'CodeWalker.Core.dll'))

$list = Get-Content -LiteralPath (Join-Path $root '_blender\ycd\m1_cf_tex.json') -Raw | ConvertFrom-Json
$textures = New-Object 'System.Collections.Generic.List[CodeWalker.GameFiles.Texture]'
foreach ($p in $list.PSObject.Properties) {
    $file = Join-Path $root "_blender\tex\$($p.Value)"
    $tex = [CodeWalker.Utils.DDSIO]::GetTexture([IO.File]::ReadAllBytes($file))
    $tex.Name = $p.Name
    $tex.NameHash = [CodeWalker.GameFiles.JenkHash]::GenHash($p.Name.ToLowerInvariant())
    $textures.Add($tex)
}

$td = New-Object CodeWalker.GameFiles.TextureDictionary
$td.BuildFromTextureList($textures)
$ytd = New-Object CodeWalker.GameFiles.YtdFile
$ytd.TextureDict = $td
$bytes = $ytd.Save()
$dst = Join-Path $root 'stream\m1_cf_tex.ytd'
[IO.File]::WriteAllBytes($dst, $bytes)

# Kontrol: læs filen igen
$check = [IO.File]::ReadAllBytes($dst)
$entry = [CodeWalker.GameFiles.RpfFile]::CreateResourceFileEntry([ref]$check, 0)
$entry.Name = 'm1_cf_tex.ytd'
$y = New-Object CodeWalker.GameFiles.YtdFile
$y.Load([CodeWalker.GameFiles.ResourceBuilder]::Decompress($check), $entry)
"Skrev $dst ($($bytes.Length) bytes): $($y.TextureDict.Textures.data_items.Count) teksturer, fx " +
    (($y.TextureDict.Textures.data_items | Select-Object -First 3 | ForEach-Object { "$($_.Name) $($_.Width)x$($_.Height) $($_.Format) mips=$($_.Levels)" }) -join '; ')
