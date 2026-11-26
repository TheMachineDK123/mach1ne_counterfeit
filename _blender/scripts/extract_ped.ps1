# Henter freemode-pedens skelet (+ basis-tøj til preview) ud af GTA V's RPF-arkiver som Sollumz-XML.
# Bruger den nøgle CodeWalker allerede har gemt lokalt. Filerne bruges kun i Blender og bliver ikke streamet.
#   powershell -File extract_ped.ps1
param(
    [string]$CodeWalker = "$env:USERPROFILE\Desktop\CodeWalker30_dev46\CodeWalker30_dev46",
    [string]$Gta = "C:\Program Files (x86)\Steam\steamapps\common\Grand Theft Auto V",
    [string[]]$Names = @('mp_m_freemode_01.yft')
)
$out = Join-Path (Split-Path -Parent $PSScriptRoot) 'ped'
New-Item -ItemType Directory -Force $out | Out-Null
[void][Reflection.Assembly]::LoadFrom((Join-Path $CodeWalker 'CodeWalker.Core.dll'))

$cfg = Get-ChildItem "$env:LOCALAPPDATA\dexyfex_software\CodeWalker.exe_*\*\user.config" | Select-Object -First 1
$key = ([xml](Get-Content -LiteralPath $cfg.FullName)).SelectSingleNode("//setting[@name='Key']/value").InnerText
[CodeWalker.GameFiles.GTA5Keys]::LoadFromPath($Gta, $key)

$rpf = New-Object CodeWalker.GameFiles.RpfFile((Join-Path $Gta 'x64v.rpf'), 'x64v.rpf')
$rpf.ScanStructure($null, $null)
$found = @{}
function Walk($r) {
    foreach ($e in $r.AllEntries) {
        if ($e -isnot [CodeWalker.GameFiles.RpfFileEntry]) { continue }
        if ($Names -contains $e.Name) { $script:found[$e.Path] = $e }
        elseif ($e.Path -like '*streamedpeds_mp.rpf\mp_m_freemode_01\*' -and $e.Name -match '^(head|uppr|lowr|feet|hand)_000_[ru]\.ydd$') { $script:found[$e.Path] = $e }
    }
    foreach ($c in $r.Children) { Walk $c }
}
Walk $rpf
foreach ($e in $found.Values) {
    $data = $e.File.ExtractFile($e)
    switch -Wildcard ($e.Name) {
        '*.yft' { $f = New-Object CodeWalker.GameFiles.YftFile; $f.Load($data, $e); $xml = [CodeWalker.GameFiles.YftXml]::GetXml($f, $out) }
        '*.ydd' { $f = New-Object CodeWalker.GameFiles.YddFile; $f.Load($data, $e); $xml = [CodeWalker.GameFiles.YddXml]::GetXml($f, $out) }
        default { }
    }
    [IO.File]::WriteAllText((Join-Path $out ($e.Name + '.xml')), $xml)
    "$($e.Name) -> $($xml.Length) tegn"
}
