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
-- All 3 mark variants ship with Ogryn's normal slow dodge/sprint templates
-- ("ogryn_fast"/"ogryn_assault") despite being a small fast weapon.
--
-- IMPORTANT: the engine "preparses" every weapon template's *_template
-- string fields (dodge_template, sprint_template, stamina_template,
-- weapon_handling_template, etc.) exactly ONCE, at the top of
-- weapon_templates.lua, the first time that module is required -- which
-- happens well before any mod script runs. Preparsing renames the field in
-- place (e.g. "ogryn_fast" -> "base_ogryn_fast") and caches a name->table
-- lookup keyed off whatever string was there AT THAT TIME. Reassigning
-- weapon_template.dodge_template to a different string afterward (what an
-- earlier version of this mod did) is therefore a silent no-op for anything
-- that reads the resolved template (confirmed: it produced zero in-game
-- difference), and pointing stamina_template at a brand-new key that didn't
-- exist at preparse time crashes outright, because the resolved-template
-- lookup never learns the new name (confirmed via a real crash log:
-- scripts/utilities/weapon_stats.lua:422, "attempt to index local
-- 'stamina_template' (a nil value)").
--
-- The correct, crash-safe fix is to leave dodge_template/sprint_template/
-- stamina_template exactly as vanilla set them, and instead overwrite the
-- CONTENTS of the templates they already resolve to -- those are read fresh
-- on every use, not cached at preparse time.
local weapon_dodge_templates = require("scripts/settings/dodge/weapon_dodge_templates")
local weapon_sprint_templates = require("scripts/settings/sprint/weapon_sprint_templates")
local weapon_stamina_templates = require("scripts/settings/stamina/weapon_stamina_templates")
local ogryn_combatblade_templates = {
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m1"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m2"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m3"),
}
local ogryn_combatblade_template_set = {}
for _, weapon_template in ipairs(ogryn_combatblade_templates) do
    ogryn_combatblade_template_set[weapon_template] = true
end

local ogryn_combatblade_move_speed = 5.8
local ogryn_combatblade_heavy_total_time = 1
local ogryn_combatblade_heavy_actions = { "action_left_heavy", "action_right_heavy" }

-- "ogryn_fast"/"ogryn_assault" are exclusive to the Combat Blade family (no
-- other Ogryn weapon references them), so overwriting their fields in place
-- is safe -- verified via a repo-wide search before writing this. Every
-- field copied from ninja_knife/ninja_l (the real Combat Knife's dodge and
-- sprint templates) by reference, not by hand-copied literal, so this stays
-- correct even if a future game patch changes those numbers.
local function apply_ogryn_combatblade_dodge_and_sprint()
    local ninja_knife_dodge = weapon_dodge_templates.ninja_knife
    local ogryn_fast_dodge = weapon_dodge_templates.ogryn_fast
    for key, value in pairs(ninja_knife_dodge) do
        ogryn_fast_dodge[key] = value
    end

    local ninja_l_sprint = weapon_sprint_templates.ninja_l
    local ogryn_assault_sprint = weapon_sprint_templates.ogryn_assault
    for key, value in pairs(ninja_l_sprint) do
        ogryn_assault_sprint[key] = value
    end
end

apply_ogryn_combatblade_dodge_and_sprint()

-- TEMPORARY diagnostic: confirms the source-table mutation above actually
-- took effect, and separately confirms what the engine's per-call resolver
-- (WeaponTweakTemplates.create, hooked below) produces for the Combat Blade
-- at actual weapon-resolve time. Needed because the user reports no dodge/
-- sprint difference at all (neither in the stats panel nor in gameplay
-- feel) despite the source values changing here -- this will show whether
-- the mutation landed, and whether the resolved (post-lerp) values the game
-- actually uses reflect it. Remove once confirmed working.
mod:echo(
    "BetterTide: ogryn_fast dodge after mutation -- distance_scale.lerp_perfect="
        .. tostring(weapon_dodge_templates.ogryn_fast.distance_scale.lerp_perfect)
        .. " speed_modifier.lerp_perfect="
        .. tostring(weapon_dodge_templates.ogryn_fast.speed_modifier.lerp_perfect)
        .. " base_distance="
        .. tostring(weapon_dodge_templates.ogryn_fast.base_distance)
)
mod:echo(
    "BetterTide: ogryn_assault sprint after mutation -- sprint_speed_mod.lerp_basic="
        .. tostring(weapon_sprint_templates.ogryn_assault.sprint_speed_mod.lerp_basic)
        .. " sprint_forward_acceleration.lerp_perfect="
        .. tostring(weapon_sprint_templates.ogryn_assault.sprint_forward_acceleration.lerp_perfect)
)

-- Stamina's vanilla template ("default") is shared with the Powermaul, so
-- overwriting it in place would buff that weapon too. Instead, hook the
-- per-call template resolver (WeaponTweakTemplates.create) and only patch
-- the resolved stamina values when the weapon being resolved is one of the
-- 3 Combat Blade templates -- every other weapon using "default" (including
-- the Powermaul) is completely unaffected.
--
-- WeaponTweakTemplates.create() returns ALREADY-RESOLVED templates: every
-- {lerp_basic, lerp_perfect} pair in the raw source table has already been
-- collapsed into a single plain number by the engine's own lerp step. An
-- earlier version of this hook assigned combat_knife_p1's RAW (unresolved)
-- lerp-pair tables directly into that resolved structure -- a table where
-- the UI stats code expects a number, which crashed instantly on opening
-- the weapon inspect panel (confirmed via crash log: math.lua:28,
-- "attempt to compare number with table", inside math.clamp). Fixed by
-- assigning plain, already-resolved numbers instead -- combat_knife_p1's
-- lerp_perfect (best-case/lowest-cost) values, matching a maxed-quality
-- knife's actual resolved cost profile.
local WeaponTweakTemplates = require("scripts/extension_systems/weapon/utilities/weapon_tweak_templates")
local WeaponTweakTemplateSettings = require("scripts/settings/equipment/weapon_templates/weapon_tweak_template_settings")
local template_types = WeaponTweakTemplateSettings.template_types
local ogryn_combatblade_stamina_modifier = 7
local ogryn_combatblade_sprint_cost_per_second = weapon_stamina_templates.combat_knife_p1.sprint_cost_per_second.lerp_perfect
local ogryn_combatblade_block_cost_inner = weapon_stamina_templates.combat_knife_p1.block_cost_default.inner.lerp_perfect
local ogryn_combatblade_block_cost_outer = weapon_stamina_templates.combat_knife_p1.block_cost_default.outer.lerp_perfect
local ogryn_combatblade_push_cost = weapon_stamina_templates.combat_knife_p1.push_cost.lerp_perfect

-- TEMPORARY diagnostic (see above): logs once per weapon_template the first
-- time it's resolved, showing the actual RESOLVED (post-lerp) dodge/sprint
-- values the game computes at runtime -- ground truth for whether the
-- source-table mutation is reaching gameplay/UI at all. Remove once
-- confirmed working, alongside the two mod:echo calls above.
local _ogryn_combatblade_resolve_logged = {}

mod:hook(WeaponTweakTemplates, "create", function(func, lerp_values, weapon_template, override_lerp_value_or_nil)
    local templates = func(lerp_values, weapon_template, override_lerp_value_or_nil)

    if ogryn_combatblade_template_set[weapon_template] then
        local resolved_stamina_templates = templates[template_types.stamina]
        for _, resolved_stamina in pairs(resolved_stamina_templates) do
            resolved_stamina.stamina_modifier = ogryn_combatblade_stamina_modifier
            resolved_stamina.sprint_cost_per_second = ogryn_combatblade_sprint_cost_per_second
            resolved_stamina.block_cost_default = {
                inner = ogryn_combatblade_block_cost_inner,
                outer = ogryn_combatblade_block_cost_outer,
            }
            resolved_stamina.push_cost = ogryn_combatblade_push_cost
        end

        if not _ogryn_combatblade_resolve_logged[weapon_template] then
            _ogryn_combatblade_resolve_logged[weapon_template] = true

            local resolved_dodge_templates = templates[template_types.dodge]
            for dodge_key, resolved_dodge in pairs(resolved_dodge_templates) do
                mod:echo(
                    "BetterTide: resolved dodge template '"
                        .. tostring(dodge_key)
                        .. "' for combat blade -- distance_scale="
                        .. tostring(resolved_dodge.distance_scale)
                        .. " speed_modifier="
                        .. tostring(resolved_dodge.speed_modifier)
                        .. " base_distance="
                        .. tostring(resolved_dodge.base_distance)
                )
            end

            local resolved_sprint_templates = templates[template_types.sprint]
            for sprint_key, resolved_sprint in pairs(resolved_sprint_templates) do
                mod:echo(
                    "BetterTide: resolved sprint template '"
                        .. tostring(sprint_key)
                        .. "' for combat blade -- sprint_speed_mod="
                        .. tostring(resolved_sprint.sprint_speed_mod)
                        .. " sprint_forward_acceleration="
                        .. tostring(resolved_sprint.sprint_forward_acceleration)
                )
            end
        end
    end

    return templates
end)

local function apply_ogryn_combatblade_speed_and_heavy_timing()
    for _, weapon_template in ipairs(ogryn_combatblade_templates) do
        weapon_template.max_first_person_anim_movement_speed = ogryn_combatblade_move_speed

        for _, action_name in ipairs(ogryn_combatblade_heavy_actions) do
            weapon_template.actions[action_name].total_time = ogryn_combatblade_heavy_total_time
        end
    end
end

apply_ogryn_combatblade_speed_and_heavy_timing()

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
        local actions = weapon_template.actions
        actions.action_wield.total_time = rippergun_wield_time
        actions.action_zoom.total_time = rippergun_ads_time
        actions.action_zoom_fast.total_time = rippergun_ads_fast_time
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

-- The engine's spread_templates.lua does one-time post-processing at module
-- load (before any mod runs) that writes a "num_spreads" COUNT field
-- directly into still.immediate_spread.damage_hit/.shooting -- the SAME
-- table as the {pitch, yaw} array entries. Recursing _scale_numeric_leaves
-- into that whole table (an earlier version of this code did) also
-- multiplies num_spreads, corrupting an integer count into a fraction; the
-- game then does spread_type_settings[math.min(num_shots, num_spreads)],
-- and a fractional index matches no array key, crashing on the next shot
-- fired (confirmed via crash log: scripts/utilities/spread.lua:47, "attempt
-- to index local 'spread_settings' (a nil value)"). Fixed by iterating only
-- the numbered array entries (1..#entries), which skips the "num_spreads"
-- string key entirely.
local function _scale_immediate_spread_entries(entries, factor)
    for i = 1, #entries do
        _scale_numeric_leaves(entries[i], factor)
    end
end

local function apply_rippergun_accuracy()
    for _, name in ipairs(rippergun_spread_template_names) do
        local still = spread_templates[name].still
        _scale_numeric_leaves(still.randomized_spread, rippergun_spread_tighten)
        _scale_numeric_leaves(still.max_spread, rippergun_spread_tighten)
        _scale_numeric_leaves(still.continuous_spread, rippergun_spread_tighten)
        _scale_immediate_spread_entries(still.immediate_spread.damage_hit, rippergun_spread_tighten)
        _scale_immediate_spread_entries(still.immediate_spread.shooting, rippergun_spread_tighten)
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
