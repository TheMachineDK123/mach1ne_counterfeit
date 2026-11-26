# Henter vanilla clip-dictionaries (reference til ped-animationerne) som Sollumz-XML.
#   powershell -File extract_anims.ps1
param(
    [string]$CodeWalker = "$env:USERPROFILE\Desktop\CodeWalker30_dev46\CodeWalker30_dev46",
    [string]$Gta = "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V",
    [string[]]$Dicts = @('anim@amb@business@coc@coc_unpack_cut@', 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
                         'amb@prop_human_movie_bulb@base', 'mini@repair')
)
$out = Join-Path (Split-Path -Parent $PSScriptRoot) 'ped\anims'
New-Item -ItemType Directory -Force $out | Out-Null
[void][Reflection.Assembly]::LoadFrom((Join-Path $CodeWalker 'CodeWalker.Core.dll'))

$cfg = Get-ChildItem "$env:LOCALAPPDATA\dexyfex_software\CodeWalker.exe_*\*\user.config" | Select-Object -First 1
$key = ([xml](Get-Content -LiteralPath $cfg.FullName)).SelectSingleNode("//setting[@name='Key']/value").InnerText
[CodeWalker.GameFiles.GTA5Keys]::LoadFromPath($Gta, $key)

$mgr = New-Object CodeWalker.GameFiles.RpfManager
$mgr.Init($Gta, [Action[string]] {}, [Action[string]] {}, $false, $true)
$want = $Dicts | ForEach-Object { "$_.ycd".ToLowerInvariant() }
foreach ($e in $mgr.AllRpfs | ForEach-Object { $_.AllEntries }) {
    if ($e -isnot [CodeWalker.GameFiles.RpfFileEntry]) { continue }
    if ($want -notcontains $e.Name.ToLowerInvariant()) { continue }
    $data = $e.File.ExtractFile($e)
    $y = New-Object CodeWalker.GameFiles.YcdFile
    $y.Load($data, $e)
    $xml = [CodeWalker.GameFiles.YcdXml]::GetXml($y)
    [IO.File]::WriteAllText((Join-Path $out ($e.Name + '.xml')), $xml)
    "$($e.Path)  clips: " + (($y.ClipMap.Values | ForEach-Object { $_.Clip.ShortName }) -join ', ')
}
