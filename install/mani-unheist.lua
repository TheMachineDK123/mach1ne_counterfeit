-- Tilføj nederst i mani-unheist/server/_state.lua, så mach1ne_counterfeit kan se, om Union-boksen er åben.
exports('isVaultOpen', function() return Heist.vaultOpened == true end)
exports('isCrew', function(src) return Heist.crew[tonumber(src)] == true end)
