return {
    run = function()
		if not rawget(_G, "new_mod") then
			error("BetterTide must be lower than Darktide Mod Framework in your mod load order.")
		end

		new_mod("BetterTide", {
			mod_script       = "BetterTide/scripts/mods/BetterTide/BetterTide",
			mod_data         = "BetterTide/scripts/mods/BetterTide/BetterTide_data",
			mod_localization = "BetterTide/scripts/mods/BetterTide/BetterTide_localization",
		})
	end,
	packages = {},
}

