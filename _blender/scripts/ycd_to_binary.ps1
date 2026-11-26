# Konverterer Sollumz' ycd.xml (prop- og ped-animationer) til binær .ycd med CodeWalker.Core (Sollumz kan kun eksportere ycd som XML).
#   powershell -File ycd_to_binary.ps1 [-CodeWalker <mappe med CodeWalker.Core.dll>]
param(
    [string]$CodeWalker = "$env:USERPROFILE\Desktop\CodeWalker30_dev46\CodeWalker30_dev46"
)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[void][Reflection.Assembly]::LoadFrom((Join-Path $CodeWalker 'CodeWalker.Core.dll'))

foreach ($name in 'm1_cf_anims', 'm1_cf_ped') {
    $src = Join-Path $root "_blender\ycd\$name.ycd.xml"
    $dst = Join-Path $root "stream\$name.ycd"
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($src)
    $bytes = [CodeWalker.GameFiles.XmlYcd]::GetYcd($doc).Save()
    [IO.File]::WriteAllBytes($dst, $bytes)

    # Kontrol: læs filen igen og list clips
    $check = [IO.File]::ReadAllBytes($dst)
    $entry = [CodeWalker.GameFiles.RpfFile]::CreateResourceFileEntry([ref]$check, 0)
    $entry.Name = "$name.ycd"
    $ycd = New-Object CodeWalker.GameFiles.YcdFile
    $ycd.Load([CodeWalker.GameFiles.ResourceBuilder]::Decompress($check), $entry)
    "$name.ycd ($($bytes.Length) bytes): " + (($ycd.ClipMap.Values | ForEach-Object { $_.Clip.ShortName }) -join ', ')
}
