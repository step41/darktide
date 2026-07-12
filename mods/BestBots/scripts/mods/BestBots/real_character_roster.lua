-- real_character_roster.lua — fetches the account's real character roster and
-- exposes it so bot_profiles.lua can inject a real character into a bot slot
-- instead of an AI class profile. Ported from the standalone BestTeam
-- (formerly Tertium4Or5) mod during the merge into BestBots.

local _mod
local _debug_log
local _debug_enabled

-- Keyed by character_id. Cleared only on a fresh fetch (not per-mission —
-- the account's character roster doesn't change mid-session).
local _profiles = {}

-- Shared, mutable table: BestBots_data.lua's character_N dropdowns reference
-- this SAME table object as their `options` list, so populating it here
-- updates the UI in place once the fetch resolves.
local M = {}
M.character_options = {
	{ text = "character_option_none", value = "none" },
}

local function _gender_abbreviation_loc_key(gender)
	if gender == "male" then
		return "character_option_gender_male_abbreviation"
	end
	return "character_option_gender_female_abbreviation"
end

local function _archetype_display_name(archetype)
	local raw_name = Localize(archetype.archetype_name)
	return raw_name:sub(1, 1):upper() .. raw_name:sub(2)
end

local function fetch_all_profiles()
	local data_service = Managers and Managers.data_service
	local profiles_service = data_service and data_service.profiles
	if not profiles_service then
		return
	end

	profiles_service:fetch_all_profiles()
end

local function _handle_fetched_profiles(data)
	local Personalities = require("scripts/settings/character/personalities")

	table.clear(_profiles)
	table.clear(M.character_options)
	M.character_options[1] = { text = "character_option_none", value = "none" }

	for _, profile in pairs(data.profiles) do
		profile.original_name = profile.name
		_profiles[profile.character_id] = profile

		local gender_text = _mod:localize(_gender_abbreviation_loc_key(profile.gender))
		local archetype_name = _archetype_display_name(profile.archetype)
		local personality_name = Localize(Personalities[profile.lore.backstory.personality].display_name)

		M.character_options[#M.character_options + 1] = {
			text = profile.original_name .. " " .. gender_text .. " " .. personality_name .. " " .. archetype_name,
			value = profile.character_id,
		}
	end

	if _debug_enabled() then
		_debug_log(
			"real_character_roster:fetched",
			0,
			"fetched " .. tostring(#M.character_options - 1) .. " real character(s)"
		)
	end
end

function M.get_character_profile(character_id)
	return _profiles[character_id]
end

function M.register_hooks()
	_mod:hook("ProfilesService", "fetch_all_profiles", function(func, ...)
		local profiles_promise = func(...)

		profiles_promise:next(function(data)
			local ok, err = pcall(_handle_fetched_profiles, data)
			if not ok and _mod.warning then
				_mod:warning("BestBots: real_character_roster failed to process fetched profiles: " .. tostring(err))
			end
		end)

		return profiles_promise
	end)

	local ProfileUtils = require("scripts/utilities/profile_utils")
	_mod:hook(ProfileUtils, "generate_random_name", function(func, profile)
		if profile.original_name then
			return profile.original_name
		end
		return func(profile)
	end)
end

M.fetch_all_profiles = fetch_all_profiles

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
end

return M
