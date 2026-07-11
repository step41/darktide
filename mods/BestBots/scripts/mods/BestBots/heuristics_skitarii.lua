-- heuristics_skitarii.lua — ability heuristics for the Skitarii (cryptic) class.
-- The Skitarii runs on Capacitance charges (3 base). Chordclaw is the primary
-- combat ability: a guaranteed-crit forward stab that gains bonuses per charge spent.
-- Discharge (the voltaic AoE) and Precision Stance are alternate combat abilities.
-- The Servo-Skull blitz has three variants; Arc Grenade is the other blitz option.

local CHORDCLAW_THRESHOLDS = {
	aggressive = {
		min_charges = 1,
		elite_distance = 12,
		density_nearby = 2,
		density_distance = 10,
	},
	balanced = {
		min_charges = 1,
		elite_distance = 9,
		density_nearby = 3,
		density_distance = 8,
	},
	conservative = {
		min_charges = 2,
		elite_distance = 7,
		density_nearby = 4,
		density_distance = 6,
	},
}

local function _can_activate_chordclaw(context, thresholds)
	local target_distance = context.target_enemy_distance
	if not target_distance or target_distance < 2 then
		return false, "chordclaw_block_target_too_close"
	end
	if context.num_nearby == 0 and not context.priority_target_enemy then
		return false, "chordclaw_block_no_pressure"
	end
	if context.target_ally_needs_aid and (context.target_ally_distance or math.huge) <= 10 then
		return true, "chordclaw_ally_rescue"
	end
	if
		context.target_is_elite_special
		and target_distance <= thresholds.elite_distance
	then
		return true, "chordclaw_elite_special"
	end
	if context.priority_target_enemy and target_distance > 2 then
		return true, "chordclaw_priority_target"
	end
	if
		context.num_nearby >= thresholds.density_nearby
		and target_distance <= thresholds.density_distance
	then
		return true, "chordclaw_density"
	end

	return false, "chordclaw_hold"
end

local DISCHARGE_THRESHOLDS = {
	aggressive = {
		density_nearby = 2,
		toughness_threshold = 0.70,
	},
	balanced = {
		density_nearby = 3,
		toughness_threshold = 0.55,
	},
	conservative = {
		density_nearby = 4,
		toughness_threshold = 0.40,
	},
}

local function _can_activate_discharge(context, thresholds)
	if context.num_nearby == 0 then
		return false, "discharge_block_no_enemies"
	end
	if context.toughness_pct < thresholds.toughness_threshold then
		return true, "discharge_low_toughness"
	end
	if context.num_nearby >= thresholds.density_nearby then
		return true, "discharge_density"
	end
	if context.target_is_elite_special and context.num_nearby >= 1 then
		return true, "discharge_elite_special"
	end

	return false, "discharge_hold"
end

local PRECISION_STANCE_THRESHOLDS = {
	aggressive = { ranged_count = 1 },
	balanced = { ranged_count = 2 },
	conservative = { ranged_count = 3 },
}

local function _can_activate_precision_stance(context, thresholds)
	if context.num_nearby == 0 then
		return false, "precision_stance_block_no_enemies"
	end
	if context.target_enemy_type == "ranged" and (context.special_count + context.elite_count) >= thresholds.ranged_count then
		return true, "precision_stance_ranged_elites"
	end
	if context.target_is_elite_special and context.target_enemy_distance and context.target_enemy_distance > 8 then
		return true, "precision_stance_distant_priority"
	end

	return false, "precision_stance_hold"
end

return {
	template_heuristics = {
		cryptic_chordclaw = _can_activate_chordclaw,
		cryptic_discharge = _can_activate_discharge,
		cryptic_precision_stance = _can_activate_precision_stance,
	},
	heuristic_thresholds = {
		cryptic_chordclaw = CHORDCLAW_THRESHOLDS,
		cryptic_discharge = DISCHARGE_THRESHOLDS,
		cryptic_precision_stance = PRECISION_STANCE_THRESHOLDS,
	},
}