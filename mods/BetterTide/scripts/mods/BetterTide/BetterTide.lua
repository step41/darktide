local mod = get_mod("BetterTide")

---- OGRYN ----
local ogryn_archetype = require("scripts/settings/archetype/archetypes/ogryn_archetype")
local archetype_toughness_templates = require("scripts/settings/toughness/archetype_toughness_templates")
local ogryn_abilities = require("scripts/settings/ability/player_abilities/abilities/ogryn_abilities")

local ogryn_max_health = 250
local ogryn_max_toughness = 125
local ogryn_ability_charge_cd = 30
local ogryn_ability_taunt_cd = 50
local ogryn_ability_pbb_cd = 50

local function apply_ogryn_tweaks()
    ogryn_archetype.health = ogryn_max_health
    archetype_toughness_templates.ogryn.max = ogryn_max_toughness

    ogryn_abilities.ogryn_charge.cooldown = ogryn_ability_charge_cd
    ogryn_abilities.ogryn_taunt_shout.cooldown = ogryn_ability_taunt_cd
    ogryn_abilities.ogryn_ranged_stance.cooldown = ogryn_ability_pbb_cd
end

apply_ogryn_tweaks()

---- OGRYN COMBAT BLADE MOBILITY ----
-- All 3 mark variants ship with Ogryn's normal slow dodge/sprint/handling
-- templates despite being a small fast weapon. Bring them up to the same
-- mobility profile as the (non-Ogryn) Combat Knife: dodge_template,
-- sprint_template, and max_first_person_anim_movement_speed copied directly
-- from combatknife_p1_m1/m2. Heavy attacks also get the knife's fast
-- weapon_handling_template and total_time (Ogryn's heavy takes 2s start to
-- finish vs the knife's 1s) so the "heavy attack move tech" matches too.
local weapon_stamina_templates = require("scripts/settings/stamina/weapon_stamina_templates")
local ogryn_combatblade_templates = {
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m1"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m2"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m3"),
}

local ogryn_combatblade_dodge_template = "ninja_knife"
local ogryn_combatblade_sprint_template = "ninja_l"
local ogryn_combatblade_move_speed = 5.8
local ogryn_combatblade_heavy_total_time = 1
local ogryn_combatblade_heavy_handling_template = "time_scale_1_1_ninja"
local ogryn_combatblade_heavy_actions = { "action_left_heavy", "action_right_heavy" }

-- New stamina template rather than reusing "default" (also used by the
-- Powermaul) or "combat_knife_p1" (stamina_modifier 1 -- too low for the
-- requested 6-8 range). Sprint/block/push costs copied from combat_knife_p1
-- to keep the low-cost mobility feel that goes with them.
weapon_stamina_templates.ogryn_combatblade_mobile = weapon_stamina_templates.ogryn_combatblade_mobile or {
    stamina_modifier = 7,
    sprint_cost_per_second = {
        lerp_basic = 0.75,
        lerp_perfect = 0.25,
    },
    block_cost_default = {
        inner = {
            lerp_basic = 0.75,
            lerp_perfect = 0.25,
        },
        outer = {
            lerp_basic = 1.5,
            lerp_perfect = 0.5,
        },
    },
    push_cost = {
        lerp_basic = 1.25,
        lerp_perfect = 0.75,
    },
}

local function apply_ogryn_combatblade_mobility()
    for _, weapon_template in ipairs(ogryn_combatblade_templates) do
        weapon_template.dodge_template = ogryn_combatblade_dodge_template
        weapon_template.sprint_template = ogryn_combatblade_sprint_template
        weapon_template.stamina_template = "ogryn_combatblade_mobile"
        weapon_template.max_first_person_anim_movement_speed = ogryn_combatblade_move_speed

        for _, action_name in ipairs(ogryn_combatblade_heavy_actions) do
            local action = weapon_template[action_name]
            if action then
                action.total_time = ogryn_combatblade_heavy_total_time
                action.weapon_handling_template = ogryn_combatblade_heavy_handling_template
            end
        end
    end
end

apply_ogryn_combatblade_mobility()

---- OGRYN RIPPER GUN TWEAKS ----
-- Shared helper: recursively multiplies every numeric leaf in a table by
-- factor. Used below on damage ranges/thresholds, spread cones, and recoil
-- kick -- all deeply nested lerp_basic/lerp_perfect-style tables where
-- hand-listing every leaf would be huge and fragile against decompile drift.
local function _scale_numeric_leaves(node, factor)
    for key, value in pairs(node) do
        if type(value) == "table" then
            _scale_numeric_leaves(value, factor)
        elseif type(value) == "number" then
            node[key] = value * factor
        end
    end
end

local rippergun_templates = {
    require("scripts/settings/equipment/weapon_templates/ripperguns/ogryn_rippergun_p1_m1"),
    require("scripts/settings/equipment/weapon_templates/ripperguns/ogryn_rippergun_p1_m2"),
    require("scripts/settings/equipment/weapon_templates/ripperguns/ogryn_rippergun_p1_m3"),
}

-- Swap (action_wield) and ADS (action_zoom / action_zoom_fast) speed --
-- identical across all 3 marks in vanilla (1.15s wield, 1.25s ADS, 0.55s
-- fast re-aim), so one shared override covers all of them.
local rippergun_wield_time = 0.4
local rippergun_ads_time = 0.5
local rippergun_ads_fast_time = 0.25

local function apply_rippergun_speed()
    for _, weapon_template in ipairs(rippergun_templates) do
        weapon_template.action_wield.total_time = rippergun_wield_time
        weapon_template.action_zoom.total_time = rippergun_ads_time
        weapon_template.action_zoom_fast.total_time = rippergun_ads_fast_time
    end
end

apply_rippergun_speed()

-- Damage: pellet shots use a ranges.min/max lerp driven by the weapon's power
-- stat -- doubling ranges.max raises the ceiling while keeping each mark's
-- relative tiering (m1 weakest, m2/m3 strongest) intact. The weapon special
-- (verified to be the bayonet stab, not a secondary gun mode -- see
-- special_action_name = "action_stab") has no ranges block; its damage is
-- driven entirely by per-target power_distribution thresholds, so halving
-- those reaches the same effective-damage increase the pellet buff gets.
local damage_profile_templates = require("scripts/settings/damage/damage_profile_templates")
local rippergun_damage_multiplier = 2
local rippergun_special_power_divisor = 0.5

local rippergun_pellet_damage_profiles = {
    damage_profile_templates.default_rippergun_assault,
    damage_profile_templates.default_rippergun_snp,
    damage_profile_templates.rippergun_p1_m2_assault,
    damage_profile_templates.rippergun_p1_m3_assault,
}

local function apply_rippergun_damage()
    for _, damage_profile in ipairs(rippergun_pellet_damage_profiles) do
        _scale_numeric_leaves(damage_profile.ranges.max, rippergun_damage_multiplier)
    end

    local special_profile = damage_profile_templates.rippergun_weapon_special
    for _, target in pairs(special_profile.targets) do
        _scale_numeric_leaves(target.power_distribution, rippergun_special_power_divisor)
    end
end

apply_rippergun_damage()

-- Accuracy: spread controls the pellet/reticle cone (randomized_spread,
-- max_spread, continuous_spread, immediate_spread kick per shot); recoil
-- controls camera kick (rise, offset, offset_random_range). Both tightened
-- by the same factor, with decay (spread/recoil recovery speed) boosted
-- instead of reduced -- higher decay means faster recovery, which is also
-- an accuracy improvement. Template name lists are the exact, complete set
-- referenced by spread_template/recoil_template across all 3 mark files
-- (verified, not guessed -- e.g. mark 3 reuses mark 1's recoil template).
local spread_templates = require("scripts/settings/equipment/spread_templates")
local recoil_templates = require("scripts/settings/equipment/recoil_templates")
local rippergun_spread_tighten = 0.55
local rippergun_spread_recovery_boost = 1.5
local rippergun_recoil_reduce = 0.5
local rippergun_recoil_recovery_boost = 1.5

local rippergun_spread_template_names = {
    "default_rippergun_assault",
    "default_rippergun_braced",
    "rippergun_p1_m2_assault",
    "rippergun_p1_m2_braced",
    "rippergun_p1_m3_assault",
}

local rippergun_recoil_template_names = {
    "default_rippergun_assault",
    "default_rippergun_spraynpray",
    "rippergun_p1_m2_assault",
    "rippergun_p1_m2_spraynpray",
}

local function apply_rippergun_accuracy()
    for _, name in ipairs(rippergun_spread_template_names) do
        local still = spread_templates[name].still
        _scale_numeric_leaves(still.randomized_spread, rippergun_spread_tighten)
        _scale_numeric_leaves(still.max_spread, rippergun_spread_tighten)
        _scale_numeric_leaves(still.continuous_spread, rippergun_spread_tighten)
        _scale_numeric_leaves(still.immediate_spread.damage_hit, rippergun_spread_tighten)
        _scale_numeric_leaves(still.immediate_spread.shooting, rippergun_spread_tighten)
        _scale_numeric_leaves(still.decay.shooting, rippergun_spread_recovery_boost)
        _scale_numeric_leaves(still.decay.idle, rippergun_spread_recovery_boost)
    end

    for _, name in ipairs(rippergun_recoil_template_names) do
        local still = recoil_templates[name].still
        still.camera_recoil_percentage = still.camera_recoil_percentage * rippergun_recoil_reduce
        _scale_numeric_leaves(still.rise, rippergun_recoil_reduce)
        _scale_numeric_leaves(still.offset, rippergun_recoil_reduce)
        _scale_numeric_leaves(still.offset_random_range, rippergun_recoil_reduce)
        _scale_numeric_leaves(still.decay, rippergun_recoil_recovery_boost)
    end
end

apply_rippergun_accuracy()
