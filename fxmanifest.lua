fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'TheMach1neDK'
description '@TheMach1neDK | Falskmøntneri: trykpresse, tørresnor, skæremaskine og sedeltæller med prop-animationer'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@st_libs/init.lua',
    '@es_extended/imports.lua',
    'config.lua',
    'shared/util.lua',
}

client_scripts {
    'client/interact.lua',
    'client/main.lua',
    'client/screens.lua',
    'client/place.lua',
    'client/dealer.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
    'html/dui.html',
}

-- Egne props med skelet + prop-/ped-animationer og fælles teksturer (stream/). Kilde i _blender/.
data_file 'DLC_ITYP_REQUEST' 'stream/mach1ne_counterfeit.ytyp'

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'oxmysql',
    'st_libs',
}
-- ox_target er valgfri (Config.Interaction)
