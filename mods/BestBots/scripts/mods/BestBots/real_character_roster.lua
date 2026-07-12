-- real_character_roster.lua — fetches the account's real character roster and
-- indexes it by archetype, so bot_profiles.lua can transparently prefer a
-- real character's own build over the generic curated profile for whichever
-- archetype a bot slot's dropdown selects. There is no separate "pick a
-- character" UI control -- the existing per-slot archetype dropdown drives
-- both: pick "Zealot" and you get YOUR Zealot if you have one, otherwise the
-- generic Zealot build. Ported and redesigned from the standalone BestTeam
-- (formerly Tertium4Or5) mod, which used a separate character-picker dropdown;
-- merged here into the single archetype dropdown per user request.

local _mod
local _debug_log
local _debug_enabled

-- Keyed by archetype string (e.g. "zealot", "cryptic" -- matches the values
-- used by bot_slot_N_profile). If an account has multiple characters of the
-- same archetype, the first one encountered in the fetch wins -- there's only
-- one dropdown slot per archetype, so there's no way to pick between them.
-- Cleared and rebuilt on every fetch (not per-mission -- the roster doesn't
-- change mid-session).
local _profiles_by_archetype = {}

-- TEMPORARY: unconditional echoes (not gated behind Enable Debug Logs) while
-- diagnosing why real characters aren't being found. Remove once confirmed
-- working.
local function fetch_all_profiles()
	local data_service = Managers and Managers.data_service
	local profiles_service = data_service and data_service.profiles
	if not profiles_service then
		_mod:echo("BestBots: real_character_roster: data_service.profiles unavailable, skipping fetch")
		return
	end

	_mod:echo("BestBots: real_character_roster: requesting fetch_all_profiles()")
	profiles_service:fetch_all_profiles()
end

local function _handle_fetched_profiles(data)
	local real_character_count = 0

	table.clear(_profiles_by_archetype)

	for _, profile in pairs(data.profiles or {}) do
		profile.original_name = profile.name

		local archetype_key = profile.archetype and profile.archetype.name
		_mod:echo(
			"BestBots: real_character_roster: found character '"
				.. tostring(profile.name)
				.. "' archetype='"
				.. tostring(archetype_key)
				.. "'"
		)
		if archetype_key and not _profiles_by_archetype[archetype_key] then
			_profiles_by_archetype[archetype_key] = profile
		end

		real_character_count = real_character_count + 1
	end

	_mod:echo("BestBots: real_character_roster: fetched " .. tostring(real_character_count) .. " real character(s) total")
end

local M = {}

-- Returns the account's real character profile for the given archetype
-- (e.g. "zealot"), or nil if none exists / the roster hasn't fetched yet.
function M.get_character_profile_by_archetype(archetype_key)
	return _profiles_by_archetype[archetype_key]
end

function M.register_hooks()
	_mod:echo("BestBots: real_character_roster.register_hooks() running")

	local hook_ok, hook_err = pcall(function()
		_mod:hook("ProfilesService", "fetch_all_profiles", function(func, ...)
			_mod:echo("BestBots: real_character_roster: fetch_all_profiles() hook fired (caller: game or us)")

			local profiles_promise = func(...)

			profiles_promise:next(function(data)
				local ok, err = pcall(_handle_fetched_profiles, data)
				if not ok then
					_mod:echo("BestBots: real_character_roster: FAILED processing fetched profiles: " .. tostring(err))
				end
			end):catch(function(err)
				_mod:echo("BestBots: real_character_roster: fetch promise REJECTED: " .. tostring(err))
			end)

			return profiles_promise
		end)
	end)
	if not hook_ok then
		_mod:echo("BestBots: real_character_roster: FAILED to install ProfilesService hook: " .. tostring(hook_err))
	end

	local ProfileUtils = require("scripts/utilities/profile_utils")
	_mod:hook(ProfileUtils, "generate_random_name", function(func, profile)
		if profile.original_name then
			return profile.original_name
		end
		return func(profile)
	end)

	-- Best-effort immediate attempt, in addition to the state-based triggers
	-- in BestBots.lua -- harmless no-op if the backend isn't ready yet this
	-- early (mod load time).
	fetch_all_profiles()
end

M.fetch_all_profiles = fetch_all_profiles

function M.init(deps)
	_mod = deps.mod
	_debug_log = deps.debug_log
	_debug_enabled = deps.debug_enabled
end

return M
