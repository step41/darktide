local mod = get_mod("BetterTide")

-- Shared helpers used across sections below.
-- _scale_numeric_leaves: recursively multiplies every numeric leaf in a
-- table by factor. Used on deeply nested lerp_basic/lerp_perfect-style
-- tables where hand-listing every leaf would be huge and fragile against
-- decompile drift. CAUTION: only call this on a table you know contains
-- ONLY scalable data -- some engine tables mix in derived metadata fields
-- (e.g. spread_templates' num_spreads counts) that must not be scaled; see
-- the Ripper Gun accuracy section below for a real example of that trap.
local function _scale_numeric_leaves(node, factor)
    for key, value in pairs(node) do
        if type(value) == "table" then
            _scale_numeric_leaves(value, factor)
        elseif type(value) == "number" then
            node[key] = value * factor
        end
    end
end

-- _deep_copy: full recursive copy, so mutating (or scaling) the result
-- never leaks back into the source table.
local function _deep_copy(source)
    local copy = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = _deep_copy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- _scale_power_distribution_thresholds: melee/special damage profiles have
-- no ranges.min/max block (that's a ranged-pellet-only shape) -- damage is
-- driven entirely by power_distribution.attack/.impact threshold pairs
-- (lower threshold = less weapon power needed to reach max damage = higher
-- effective damage). These profiles also contain armor_damage_modifier
-- tables (lerp value ENUM references, not magnitudes) and other unrelated
-- numeric fields (finesse_boost percentages, ragdoll_push_force, etc.) at
-- the same or deeper nesting levels, so a blind _scale_numeric_leaves over
-- the whole profile would corrupt those too. This walks the full tree but
-- only ever scales the contents of a table actually named
-- "power_distribution", leaving everything else untouched.
local function _scale_power_distribution_thresholds(node, factor)
    if type(node) ~= "table" then
        return
    end

    if node.power_distribution then
        _scale_numeric_leaves(node.power_distribution, factor)
    end

    for key, value in pairs(node) do
        if key ~= "power_distribution" and type(value) == "table" then
            _scale_power_distribution_thresholds(value, factor)
        end
    end
end

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

---- OGRYN MOBILITY (dodge, sprint) -- ARCHETYPE-WIDE, ALL WEAPONS ----
-- Originally Combat Blade-only; explicitly widened to every Ogryn weapon
-- per request. Two field categories, resolved completely differently:
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
local damage_profile_templates = require("scripts/settings/damage/damage_profile_templates")
local archetype_dodge_templates = require("scripts/settings/dodge/archetype_dodge_templates")
local archetype_sprint_templates = require("scripts/settings/sprint/archetype_sprint_templates")
local ogryn_combatblade_templates = {
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m1"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m2"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m3"),
}
local ogryn_combatblade_template_set = {}
for _, weapon_template in ipairs(ogryn_combatblade_templates) do
    ogryn_combatblade_template_set[weapon_template] = true
end

-- dodge_cooldown (time before you can dodge again) and sprint_move_speed
-- have NO per-weapon override anywhere in their formulas (confirmed:
-- player_character_state_dodging.lua reads dodge_cooldown straight off
-- self._archetype_dodge_template with no weapon fallback path at all; the
-- sprint speed formula is archetype.sprint_move_speed + weapon.sprint_
-- speed_mod, additive not overridden). These are naturally universal to
-- every Ogryn weapon already -- a direct archetype mutation is both
-- correct and the simplest possible fix. An earlier version of this mod
-- used a PlayerCharacterStateDodging.on_exit hook to scope dodge_cooldown
-- to just the Combat Blade -- that hook (and the dodge-template tagging
-- that fed it, previously in the stamina hook below) is removed entirely
-- now that archetype-wide is explicitly wanted; there's nothing left to
-- scope.
archetype_dodge_templates.ogryn.dodge_cooldown = 0.05
archetype_sprint_templates.ogryn.sprint_move_speed = archetype_sprint_templates.default.sprint_move_speed

-- Dodge "count" (diminishing_return_start/limit) and the distance_scale/
-- speed_modifier multipliers only exist as WEAPON-template concepts --
-- there is no archetype equivalent field for either (confirmed: archetype_
-- dodge_templates.ogryn's schema has no distance_scale/speed_modifier/
-- diminishing_return_* keys at all). Making these "regardless of weapon
-- equipped" means touching every distinct weapon-level dodge/sprint
-- template name Ogryn actually uses, confirmed via a repo-wide search:
--   dodge:  "ogryn_fast" (Combat Blade), "ogryn" (Club, Powermaul,
--           Pickaxe, Heavystubber, Rippergun, Thumper, unarmed) -- both
--           confirmed exclusive to Ogryn, no non-Ogryn weapon references
--           either.
--   sprint: "ogryn_assault" (Combat Blade), "ogryn" (same family as
--           dodge "ogryn" plus Slabshield's sprint), "ogryn_sprint_slow"
--           (Pickaxe mark 1), "ogryn_sprint_fast" (Pickaxe mark 3) -- all
--           4 confirmed exclusive to Ogryn.
-- NOT covered: the Gauntlet (dodge AND sprint both use "default", shared
-- with dozens of non-Ogryn weapons) and the Slabshield's DODGE
-- specifically (uses "support", shared with the autogun family). Both
-- would need a weapon-instance-scoped hook (same pattern as the stamina
-- hook below) to touch safely without affecting non-Ogryn weapons --
-- left out of this pass; every other Ogryn-wieldable weapon is covered.
--
-- Deep-copy every field from ninja_knife/ninja_l rather than aliasing by
-- reference: a plain `dodge_template[key] = value` assigns the SAME nested
-- table object for any table-typed field, so a later scale would also
-- scale the REAL Combat Knife's stats for every other class that uses it
-- (Zealot included). dodge_speed_at_times is deliberately EXCLUDED from
-- the copy (unlike every other dodge field) -- it's an animation-synced
-- speed curve tuned for the knife's own swing/dodge animation, and
-- applying it to visually very different weapons (Heavystubber, Powermaul)
-- risks the same kind of animation/timing desync that broke Combat Blade
-- attack speed earlier in this file -- each weapon keeps its own curve.
local ogryn_dodge_template_names = { "ogryn_fast", "ogryn" }
local ogryn_dodge_fields_to_copy = {
    "base_distance",
    "consecutive_dodges_reset",
    "distance_scale",
    "diminishing_return_distance_modifier",
    "diminishing_return_start",
    "diminishing_return_limit",
    "speed_modifier",
}
local ogryn_sprint_template_names = { "ogryn_assault", "ogryn", "ogryn_sprint_slow", "ogryn_sprint_fast" }
-- Confirmed working (not flagged as "too much" the way dodge distance and
-- heavy-attack movement were, both already dialed back to 1x/0.5x
-- elsewhere in this file) -- kept as the accepted baseline rather than
-- reverted to 1x knife-parity.
local ogryn_sprint_speed_multiplier = 3

local function apply_ogryn_mobility()
    local ninja_knife_dodge = weapon_dodge_templates.ninja_knife
    for _, name in ipairs(ogryn_dodge_template_names) do
        local dodge_template = weapon_dodge_templates[name]
        for _, field_name in ipairs(ogryn_dodge_fields_to_copy) do
            local value = ninja_knife_dodge[field_name]
            if value ~= nil then
                dodge_template[field_name] = type(value) == "table" and _deep_copy(value) or value
            end
        end
    end

    local ninja_l_sprint = weapon_sprint_templates.ninja_l
    for _, name in ipairs(ogryn_sprint_template_names) do
        local sprint_template = weapon_sprint_templates[name]
        for key, value in pairs(ninja_l_sprint) do
            sprint_template[key] = type(value) == "table" and _deep_copy(value) or value
        end
        _scale_numeric_leaves(sprint_template.sprint_speed_mod, ogryn_sprint_speed_multiplier)
        _scale_numeric_leaves(sprint_template.sprint_forward_acceleration, ogryn_sprint_speed_multiplier)
    end
end

apply_ogryn_mobility()

---- OGRYN COMBAT BLADE ----
local ogryn_combatblade_mobility_multiplier = 1
-- Heavy-attack forward movement (below) was reported "too much" even at
-- knife parity (1x), so this needs its own dial, halving it below parity.
local ogryn_combatblade_heavy_movement_multiplier = 0.5
local ogryn_combatblade_move_speed = 5.8 * ogryn_combatblade_mobility_multiplier
local ogryn_combatblade_heavy_total_time = 1
local ogryn_combatblade_heavy_actions = { "action_left_heavy", "action_right_heavy" }

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
-- lerp_perfect (best-case/lowest-cost) values, halved again for "minimal"
-- cost per explicit user request.
local WeaponTweakTemplates = require("scripts/extension_systems/weapon/utilities/weapon_tweak_templates")
local WeaponTweakTemplateSettings = require("scripts/settings/equipment/weapon_templates/weapon_tweak_template_settings")
local template_types = WeaponTweakTemplateSettings.template_types
local ogryn_combatblade_stamina_modifier = 7 * ogryn_combatblade_mobility_multiplier
local ogryn_combatblade_sprint_cost_per_second = weapon_stamina_templates.combat_knife_p1.sprint_cost_per_second.lerp_perfect
    / ogryn_combatblade_mobility_multiplier
local ogryn_combatblade_block_cost_inner = weapon_stamina_templates.combat_knife_p1.block_cost_default.inner.lerp_perfect
    / ogryn_combatblade_mobility_multiplier
local ogryn_combatblade_block_cost_outer = weapon_stamina_templates.combat_knife_p1.block_cost_default.outer.lerp_perfect
    / ogryn_combatblade_mobility_multiplier
local ogryn_combatblade_push_cost = weapon_stamina_templates.combat_knife_p1.push_cost.lerp_perfect
    / ogryn_combatblade_mobility_multiplier

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
    end

    return templates
end)

-- action_movement_curve.modifier values are multipliers applied to the
-- character's current move speed while the heavy attack plays (confirmed
-- via WeaponActionMovement.move_speed_modifier) -- this is what produces
-- forward distance when moving + heavy-attacking together. Scales only
-- .modifier (and .start_modifier, if present) -- .t is a normalized time
-- position (0-1) along the swing, not a magnitude, so it must stay as-is
-- or the curve's timing desyncs from the attack animation.
local function _scale_movement_curve_modifiers(action_movement_curve, factor)
    if action_movement_curve.start_modifier then
        action_movement_curve.start_modifier = action_movement_curve.start_modifier * factor
    end

    for i = 1, #action_movement_curve do
        action_movement_curve[i].modifier = action_movement_curve[i].modifier * factor
    end
end

local function apply_ogryn_combatblade_speed_and_heavy_timing()
    for _, weapon_template in ipairs(ogryn_combatblade_templates) do
        weapon_template.max_first_person_anim_movement_speed = ogryn_combatblade_move_speed

        for _, action_name in ipairs(ogryn_combatblade_heavy_actions) do
            local action = weapon_template.actions[action_name]
            action.total_time = ogryn_combatblade_heavy_total_time

            if action.action_movement_curve then
                _scale_movement_curve_modifiers(action.action_movement_curve, ogryn_combatblade_heavy_movement_multiplier)
            end
        end
    end
end

apply_ogryn_combatblade_speed_and_heavy_timing()

-- Damage, discovered structurally rather than by a hardcoded action-name
-- list -- the 3 marks turned out to use genuinely different action sets
-- for their light-attack chains (m1/m2: action_left_light/
-- action_right_light, m2 also has a separate action_light_pushfollow_combo,
-- m3 instead uses action_light_1/2/3) and different damage profile names
-- per mark (e.g. m2 alone references combat_blade_smiter_pushfollow). A
-- hardcoded list would silently miss actions on whichever mark doesn't use
-- that exact name.
--
-- Any action with a `damage_profile` field is a real attack (verified: no
-- non-attack action -- block/push/wield/unwield/melee_start_*/inspect --
-- has this exact field; action_push has inner_damage_profile/
-- outer_damage_profile instead, a different key, so it's correctly
-- excluded).
--
-- Melee/special damage profiles have no ranges.min/max block (that's the
-- ranged-pellet-only shape used by the Ripper Gun below) -- damage is
-- driven entirely by power_distribution.attack/.impact threshold pairs, so
-- dividing those by the multiplier raises effective damage the same way
-- lowering the Ripper Gun's bayonet-special thresholds did. Every
-- combat_blade_*-prefixed profile (and special_uppercut_plus) is confirmed
-- exclusive to this weapon family via a repo-wide search, so in-place
-- mutation is safe -- no shared-table risk, unlike stamina's "default".
-- Deduplicated by table identity across ALL 3 marks (not reset per mark)
-- since some damage profile objects are the same shared table referenced
-- by more than one mark/action -- without this, scaling would compound
-- (e.g. 2x becomes 4x) wherever that overlap happens.
--
-- NOTE: attack SPEED (scaling total_time) was tried here and reverted --
-- it broke combo chaining, cut animations short, and made attacks miss
-- entirely. Root cause: hit registration (damage_window_start/.end) and
-- combo-chain advancement (chain_time) are both computed against a
-- SEPARATE `time_scale` value derived from weapon_handling_template, not
-- from total_time (confirmed in scripts/extension_systems/weapon/actions/
-- action_sweep.lua's _is_within_damage_window: damage_window_end /
-- time_scale, compared directly against elapsed action time). Shrinking
-- total_time alone left the action ending/transitioning away before its
-- own (unmoved) damage window and chain-advance point were ever reached.
-- A correct fix needs to speed up time_scale in step with total_time, but
-- weapon_handling_template is a *_template string -- same preparse-rename
-- hazard as dodge_template/sprint_template/stamina_template -- so it needs
-- a proper runtime hook (like the stamina and dodge_cooldown hooks above),
-- not a source-table edit. Left for a follow-up rather than shipping
-- another guess.
local ogryn_combatblade_damage_multiplier = 2
local ogryn_combatblade_scaled_damage_profiles = {}

local function apply_ogryn_combatblade_damage()
    for _, weapon_template in ipairs(ogryn_combatblade_templates) do
        for _, action in pairs(weapon_template.actions) do
            if action.damage_profile and not ogryn_combatblade_scaled_damage_profiles[action.damage_profile] then
                ogryn_combatblade_scaled_damage_profiles[action.damage_profile] = true
                _scale_power_distribution_thresholds(action.damage_profile, 1 / ogryn_combatblade_damage_multiplier)
            end
        end
    end
end

apply_ogryn_combatblade_damage()

-- Guaranteed 100% crit chance. Traced the real crit roll to
-- scripts/extension_systems/weapon/actions/action_weapon_base.lua:
-- chance = prevent_crit and 0 or guaranteed_crit and 1 or
-- CriticalStrike.chance(...) -- where guaranteed_crit is true if any of
-- several buff keywords are set OR action_auto_crit is set, and
-- action_auto_crit traces (action_sweep.lua) to a plain
-- action_settings.guaranteed_crit boolean read directly off the action
-- table -- the same actions already touched throughout this file. Not a
-- *_template string, not preparse-cached, no hook needed -- a category-A
-- safe direct field, same as total_time/damage_profile edits already
-- above. (prevent_crit still overrides this to 0 when set -- e.g. a boss
-- that's flagged immune to crits stays immune, which is correct.)
local function apply_ogryn_combatblade_guaranteed_crit()
    for _, weapon_template in ipairs(ogryn_combatblade_templates) do
        for _, action in pairs(weapon_template.actions) do
            if action.damage_profile then
                action.guaranteed_crit = true
            end
        end
    end
end

apply_ogryn_combatblade_guaranteed_crit()

-- Armor penetration / rending, take 2. The first attempt here added a
-- weapon_template.overclocks table -- WRONG, confirmed dead: a repo-wide
-- search of the entire scripts/ui tree found zero UI files reference
-- .overclocks at all, on ANY weapon, for ANY class. Nothing in the shipped
-- game ever sets item.overclocks, so
-- WeaponTweakTemplates.calculate_lerp_values's overclock lookup always
-- iterates an empty table -- the table this mod added was never read.
-- Removed entirely rather than left in place doing nothing.
--
-- The REAL crafting mechanism players actually use is weapon_template.perks
-- (confirmed live: consumed by view_element_perks_item*/
-- view_element_crafting_recipe.lua) -- structurally similar to base_stats
-- but a fully separate, independent crafting slot (its own
-- damage_trait_templates.default_X_perk trait, not tied to whether a
-- matching base_stats entry exists). The real Combat Knife has 5 entries
-- here (dps/armor_pierce/finesse/first_target/mobility perks);
-- weapon_template.perks is completely UNDEFINED on all 3 Ogryn Combat
-- Blade marks -- confirmed via direct grep, zero matches. An Ogryn player
-- has no perk slot to invest in armor pierce at all, where a knife user
-- does.
--
-- Added only armor_pierce_perk (the one the user actually asked about) --
-- discovered structurally (any action with a damage_profile field, same
-- method as the damage-scaling pass above) rather than hardcoding action
-- names, since the 3 marks use different action sets. display_name reuses
-- the real knife's own loc key (loc_trait_display_combatknife_p1_m1_
-- armor_pierce_perk) -- BetterTide has no localization entry of its own
-- for this, and the knife's key already resolves to sensible generic
-- "Armor Piercing" text that applies equally well here.
local DamageTraitTemplates =
    require("scripts/settings/equipment/weapon_templates/weapon_trait_templates/damage_trait_templates")

local function apply_ogryn_combatblade_armor_pierce_perk()
    for _, weapon_template in ipairs(ogryn_combatblade_templates) do
        weapon_template.perks = weapon_template.perks or {}

        local armor_pierce_perk_damage = {}
        for action_name, action in pairs(weapon_template.actions) do
            if action.damage_profile then
                armor_pierce_perk_damage[action_name] = { DamageTraitTemplates.default_armor_pierce_perk }
            end
        end

        weapon_template.perks.ogryn_combatblade_p1_m1_armor_pierce_perk = {
            display_name = "loc_trait_display_combatknife_p1_m1_armor_pierce_perk",
            damage = armor_pierce_perk_damage,
        }
    end
end

apply_ogryn_combatblade_armor_pierce_perk()

-- combat_blade_light_linesman: the one genuinely worse per-hit armor
-- profile found. Its DOMINANT damage component against a primary target is
-- "attack" (power_distribution.attack ~100-200 vs impact's ~7-14, i.e.
-- attack contributes the overwhelming majority of actual damage dealt),
-- and that component's super_armor modifier is far below the real knife's
-- equivalent (medium_combat_knife_linesman): Ogryn primary-target attack
-- modifier 0.05 vs the knife's 0.5 for the same dominant component and
-- role. Ogryn's impact-component modifier is actually fine/better (0.5 vs
-- the knife's 0), but impact barely contributes to total damage here, so
-- it doesn't compensate. Bumped the "attack" component's super_armor
-- modifier across the top-level fallback and every target tier, roughly
-- matching the knife's own tiering (primary target highest, secondary
-- lower, splash/default lowest).
local ArmorSettings = require("scripts/settings/damage/armor_settings")
local DamageProfileSettings = require("scripts/settings/damage/damage_profile_settings")
local armor_types = ArmorSettings.types
local damage_lerp_values = DamageProfileSettings.damage_lerp_values

local function apply_ogryn_combatblade_linesman_penetration()
    local linesman = damage_profile_templates.combat_blade_light_linesman
    linesman.armor_damage_modifier.attack[armor_types.super_armor] = damage_lerp_values.lerp_0_5
    linesman.targets[1].armor_damage_modifier.attack[armor_types.super_armor] = damage_lerp_values.lerp_0_5
    linesman.targets[2].armor_damage_modifier.attack[armor_types.super_armor] = damage_lerp_values.lerp_0_1
    linesman.targets.default_target.armor_damage_modifier.attack[armor_types.super_armor] = damage_lerp_values.lerp_0_25
end

apply_ogryn_combatblade_linesman_penetration()

-- special_uppercut_plus (Ogryn's special attack, already 2x damage-buffed
-- above): default_target.power_distribution.attack = 0 (a flat zero, not a
-- {min,max} range like every other target here) -- meaning the "attack"
-- component's armor modifiers are already moot for this target regardless
-- of value, since 0 times anything is 0. The component that actually
-- matters is "impact" (power_distribution.impact = 1), and its
-- super_armor modifier is set to no_damage -- a real zero, and an
-- inconsistent one: this same profile's own top-level fallback
-- (armor_damage_modifier.impact[super_armor]) already uses lerp_0_5, which
-- targets 1-3 correctly inherit (they don't override armor_damage_modifier
-- at all) -- only default_target overrides it down to no_damage. Fixed to
-- match the profile's own established value instead of introducing a new
-- one.
local function apply_ogryn_combatblade_uppercut_fix()
    local uppercut = damage_profile_templates.special_uppercut_plus
    uppercut.targets.default_target.armor_damage_modifier.impact[armor_types.super_armor] = damage_lerp_values.lerp_0_5
end

apply_ogryn_combatblade_uppercut_fix()

---- OGRYN RIPPER GUN TWEAKS ----
-- _scale_numeric_leaves is defined at the top of the file (shared helper).
local rippergun_templates = {
    require("scripts/settings/equipment/weapon_templates/ripperguns/ogryn_rippergun_p1_m1"),
    require("scripts/settings/equipment/weapon_templates/ripperguns/ogryn_rippergun_p1_m2"),
    require("scripts/settings/equipment/weapon_templates/ripperguns/ogryn_rippergun_p1_m3"),
}

-- Swap (action_wield) and ADS (action_zoom / action_zoom_fast) speed --
-- identical across all 3 marks in vanilla (1.15s wield, 1.25s ADS, 0.55s
-- fast re-aim), so one shared override covers all of them. ADS pushed to
-- near-instant (0.12s) per explicit request -- the earlier 0.5s target was
-- still "way too slow".
local rippergun_wield_time = 0.4
local rippergun_ads_time = 0.12
local rippergun_ads_fast_time = 0.08

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
-- (damage_profile_templates required near the top of the file, shared with
-- the Combat Blade damage section above.)
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
