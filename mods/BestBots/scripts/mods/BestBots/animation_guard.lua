-- animation_guard.lua — degrade invalid bot anim-event variable writes to a
-- plain anim event so bot-only item abilities cannot crash the animation path.
-- luacheck: globals Unit
local _mod -- luacheck: ignore 231

local function _hook_require_now(path, callback)
	local hook_require_now = _mod and _mod.hook_require_now
	if hook_require_now then
		return hook_require_now(_mod, path, callback, 4)
	end

	if _mod and _mod.warning and _mod._raw_hook_require then
		_mod:warning("BestBots: hook_require_now_missing for " .. tostring(path))
	end
	return _mod["hook_require"](_mod, path, callback)
end

local _debug_log
local _debug_enabled
local _fixed_time

local INVALID_ANIMATION_VARIABLE_INDEX = 4294967295
local ANIMATION_EXTENSION_SENTINEL = "__bb_animation_guard_installed"

local function is_valid_variable_index(variable_index)
	return variable_index ~= nil and variable_index ~= INVALID_ANIMATION_VARIABLE_INDEX
end

local function _is_bot_unit(self)
	local player = self and self._player
	return player and player.is_human_controlled and not player:is_human_controlled()
end

local function _is_unit_animation_valid(unit)
	if not unit then
		return false
	end
	local ok, result = pcall(Unit.alive, unit)
	return ok and result == true
end

local function _is_fp_unit_animation_valid(self)
	local fp_unit = self and self._first_person_unit
	return _is_unit_animation_valid(fp_unit)
end

local function _safe_animation_find_variable(unit, variable_name)
	local ok, variable_index = pcall(Unit.animation_find_variable, unit, variable_name)
	if not ok then
		return nil, "lookup_failed"
	end

	if not is_valid_variable_index(variable_index) then
		return nil, "invalid_variable"
	end

	return variable_index
end

local function register_hooks()
	_hook_require_now(
		"scripts/extension_systems/animation/authoritative_player_unit_animation_extension",
		function(AuthoritativePlayerUnitAnimationExtension)
			if
				not AuthoritativePlayerUnitAnimationExtension
				or rawget(AuthoritativePlayerUnitAnimationExtension, ANIMATION_EXTENSION_SENTINEL)
			then
				return
			end

			AuthoritativePlayerUnitAnimationExtension[ANIMATION_EXTENSION_SENTINEL] = true

			-- Guard anim_event_with_variable_float (line 77)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_with_variable_float",
				function(func, self, event_name, variable_name, variable_value)
					if not _is_bot_unit(self) then
						return func(self, event_name, variable_name, variable_value)
					end

					local unit = self and self._unit
					if not _is_unit_animation_valid(unit) then
						return
					end

					local variable_index, failure_reason = _safe_animation_find_variable(unit, variable_name)

					if not variable_index then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:float:" .. tostring(variable_name) .. ":" .. tostring(failure_reason),
								_fixed_time(),
								"animation guard fell back to plain anim_event for float "
									.. tostring(variable_name)
									.. " ("
									.. tostring(failure_reason)
									.. ")",
								nil,
								"info"
							)
						end

						return self:anim_event(event_name)
					end

					return func(self, event_name, variable_name, variable_value)
				end
			)

			-- Guard anim_event (plain)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event",
				function(func, self, event_name)
					if not _is_bot_unit(self) then
						return func(self, event_name)
					end

					local unit = self and self._unit
					if not _is_unit_animation_valid(unit) then
						return
					end

					local ok = pcall(func, self, event_name)
					if not ok then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:anim_event:" .. tostring(event_name),
								_fixed_time(),
								"animation guard suppressed invalid anim_event for "
									.. tostring(event_name),
								nil,
								"info"
							)
						end
					end
				end
			)

			-- Guard anim_event_with_variable_int (line 227)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_with_variable_int",
				function(func, self, event_name, variable_name, variable_value)
					if not _is_bot_unit(self) then
						return func(self, event_name, variable_name, variable_value)
					end

					local unit = self and self._unit
					if not _is_unit_animation_valid(unit) then
						return
					end

					local variable_index, failure_reason = _safe_animation_find_variable(unit, variable_name)

					if not variable_index then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:int:" .. tostring(variable_name) .. ":" .. tostring(failure_reason),
								_fixed_time(),
								"animation guard fell back to plain anim_event for int "
									.. tostring(variable_name)
									.. " ("
									.. tostring(failure_reason)
									.. ")",
								nil,
								"info"
							)
						end

						return self:anim_event(event_name)
					end

					return func(self, event_name, variable_name, variable_value)
				end
			)

			-- Guard anim_event_1p (first person plain)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_1p",
				function(func, self, event_name)
					if not _is_bot_unit(self) then
						return func(self, event_name)
					end

					if not _is_fp_unit_animation_valid(self) then
						return
					end

					local ok = pcall(func, self, event_name)
					if not ok then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:anim_event_1p:" .. tostring(event_name),
								_fixed_time(),
								"animation guard suppressed invalid anim_event_1p for "
									.. tostring(event_name),
								nil,
								"info"
							)
						end
					end
				end
			)

			-- Guard anim_event_with_variable_float_1p (first person float)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_with_variable_float_1p",
				function(func, self, event_name, variable_name, variable_value)
					if not _is_bot_unit(self) then
						return func(self, event_name, variable_name, variable_value)
					end

					local fp_unit = self and self._first_person_unit
					if not _is_unit_animation_valid(fp_unit) then
						return
					end

					local variable_index, failure_reason = _safe_animation_find_variable(fp_unit, variable_name)

					if not variable_index then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:float_1p:" .. tostring(variable_name) .. ":" .. tostring(failure_reason),
								_fixed_time(),
								"animation guard fell back to plain anim_event_1p for float "
									.. tostring(variable_name)
									.. " ("
									.. tostring(failure_reason)
									.. ")",
								nil,
								"info"
							)
						end

						return self:anim_event_1p(event_name)
					end

					return func(self, event_name, variable_name, variable_value)
				end
			)

			-- Guard anim_event_with_variable_floats (multi-float)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_with_variable_floats",
				function(func, self, event_name, ...)
					if not _is_bot_unit(self) then
						return func(self, event_name, ...)
					end

					local unit = self and self._unit
					if not _is_unit_animation_valid(unit) then
						return
					end

					local ok = pcall(func, self, event_name, ...)
					if not ok then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:floats:" .. tostring(event_name),
								_fixed_time(),
								"animation guard suppressed invalid anim_event_with_variable_floats for "
									.. tostring(event_name),
								nil,
								"info"
							)
						end

						return self:anim_event(event_name)
					end
				end
			)

			-- Guard anim_event_with_variable_floats_1p (multi-float first person)
			_mod:hook(
				AuthoritativePlayerUnitAnimationExtension,
				"anim_event_with_variable_floats_1p",
				function(func, self, event_name, ...)
					if not _is_bot_unit(self) then
						return func(self, event_name, ...)
					end

					local fp_unit = self and self._first_person_unit
					if not _is_unit_animation_valid(fp_unit) then
						return
					end

					local ok = pcall(func, self, event_name, ...)
					if not ok then
						if _debug_enabled() then
							_debug_log(
								"animation_guard:floats_1p:" .. tostring(event_name),
								_fixed_time(),
								"animation guard suppressed invalid anim_event_with_variable_floats_1p for "
									.. tostring(event_name),
								nil,
								"info"
							)
						end

						return self:anim_event_1p(event_name)
					end
				end
			)
		end
	)
end

return {
	init = function(deps)
		_mod = deps.mod
		_debug_log = deps.debug_log
		_debug_enabled = deps.debug_enabled
		_fixed_time = deps.fixed_time
	end,
	register_hooks = register_hooks,
	is_valid_variable_index = is_valid_variable_index,
	_safe_animation_find_variable = _safe_animation_find_variable,
}
