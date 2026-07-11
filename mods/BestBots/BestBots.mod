return {
	run = function()
		if not rawget(_G, "new_mod") then
			error("BestBots must be lower than Darktide Mod Framework in your mod load order.")
		end

		new_mod("BestBots", {
			mod_script       = "BestBots/scripts/mods/BestBots/BestBots",
			mod_data         = "BestBots/scripts/mods/BestBots/BestBots_data",
			mod_localization = "BestBots/scripts/mods/BestBots/BestBots_localization",
		})
	end,
	packages = {},
}
