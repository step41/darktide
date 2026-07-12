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
local damage_profile_templates = require("scripts/settings/damage/damage_profile_templates")
local ogryn_combatblade_templates = {
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m1"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m2"),
    require("scripts/settings/equipment/weapon_templates/combat_blades/ogryn_combatblade_p1_m3"),
}
local ogryn_combatblade_template_set = {}
for _, weapon_template in ipairs(ogryn_combatblade_templates) do
    ogryn_combatblade_template_set[weapon_template] = true
end

-- Dodge and heavy-attack forward movement both confirmed working (in fact
-- "way more than we want" / "about 2x what they should be") -- dialed back
-- to 1 (exact Combat Knife parity, the original ask) now that the
-- mechanism is proven. Kept for stamina too (reverts to the original 7
-- pool / combat_knife_p1 costs -- doubling stamina specifically was never
-- requested, just swept up in the "over the top" test pass).
--
-- Sprint speed is the one confirmed NOT working even at 2x -- full trace
-- confirms weapon_sprint_template.sprint_speed_mod really is the
-- authoritative term in the actual applied-velocity formula
-- (max_move_speed = archetype.sprint_move_speed(5) + weapon.sprint_speed_mod,
-- flows through to locomotion_steering.velocity_wanted with no clamp in
-- between), and the resolution mechanism is byte-for-byte identical to
-- dodge's (same accessor pattern, same WeaponTweakTemplates.create
-- pipeline) -- which IS confirmed working. Leading theory: the archetype
-- term (5) still dominated the sum even after doubling the weapon term
-- (~0.8 -> ~1.6), diluting the ~20% top-speed change enough to not read as
-- "different" next to the much larger dodge/heavy-attack changes. Testing
-- an extreme, dedicated multiplier here (separate from the mobility
-- multiplier above) to get a definitive signal: if this still produces zero
-- difference, that's strong evidence of an actual bug worth digging into
-- further rather than a magnitude problem.
local ogryn_combatblade_mobility_multiplier = 1
local ogryn_combatblade_sprint_test_multiplier = 5
local ogryn_combatblade_move_speed = 5.8 * ogryn_combatblade_mobility_multiplier
local ogryn_combatblade_heavy_total_time = 1
local ogryn_combatblade_heavy_actions = { "action_left_heavy", "action_right_heavy" }

-- "ogryn_fast"/"ogryn_assault" are exclusive to the Combat Blade family (no
-- other Ogryn weapon references them), so overwriting their fields in place
-- is safe -- verified via a repo-wide search before writing this. Deep-copy
-- every field from ninja_knife/ninja_l rather than aliasing by reference:
-- a plain `ogryn_fast_dodge[key] = value` (an earlier version of this code)
-- assigns the SAME nested table object for any table-typed field, so
-- scaling it afterward would also scale the REAL Combat Knife's stats for
-- every other class that uses it (Zealot included). Left unscaled:
-- diminishing_return_distance_modifier (a falloff curve shape, not a
-- magnitude) and dodge_speed_at_times (an animation-synced speed curve --
-- doubling it would desync the visual dodge animation from the actual
-- movement).
local function apply_ogryn_combatblade_dodge_and_sprint()
    local ninja_knife_dodge = weapon_dodge_templates.ninja_knife
    local ogryn_fast_dodge = weapon_dodge_templates.ogryn_fast
    for key, value in pairs(ninja_knife_dodge) do
        if type(value) == "table" then
            ogryn_fast_dodge[key] = _deep_copy(value)
        else
            ogryn_fast_dodge[key] = value
        end
    end
    ogryn_fast_dodge.base_distance = ogryn_fast_dodge.base_distance * ogryn_combatblade_mobility_multiplier
    _scale_numeric_leaves(ogryn_fast_dodge.distance_scale, ogryn_combatblade_mobility_multiplier)
    _scale_numeric_leaves(ogryn_fast_dodge.speed_modifier, ogryn_combatblade_mobility_multiplier)
    _scale_numeric_leaves(ogryn_fast_dodge.diminishing_return_start, ogryn_combatblade_mobility_multiplier)
    _scale_numeric_leaves(ogryn_fast_dodge.diminishing_return_limit, ogryn_combatblade_mobility_multiplier)

    local ninja_l_sprint = weapon_sprint_templates.ninja_l
    local ogryn_assault_sprint = weapon_sprint_templates.ogryn_assault
    for key, value in pairs(ninja_l_sprint) do
        if type(value) == "table" then
            ogryn_assault_sprint[key] = _deep_copy(value)
        else
            ogryn_assault_sprint[key] = value
        end
    end
    _scale_numeric_leaves(ogryn_assault_sprint.sprint_speed_mod, ogryn_combatblade_sprint_test_multiplier)
    _scale_numeric_leaves(ogryn_assault_sprint.sprint_forward_acceleration, ogryn_combatblade_sprint_test_multiplier)
end

apply_ogryn_combatblade_dodge_and_sprint()

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

        -- Tagged so the dodge-frequency hook below can recognize "the
        -- currently equipped weapon's resolved dodge template is one of
        -- ours" -- self._weapon_extension:dodge_template() returns this
        -- exact RESOLVED (post-lerp) table, not the raw source table
        -- mutated above, so an identity check against
        -- weapon_dodge_templates.ogryn_fast would never match it.
        local resolved_dodge_templates = templates[template_types.dodge]
        for _, resolved_dodge in pairs(resolved_dodge_templates) do
            resolved_dodge._bettertide_ogryn_combatblade = true
        end
    end

    return templates
end)

-- dodge_cooldown (time before you can dodge again) and
-- consecutive_dodges_reset (time before the diminishing-return dodge
-- counter resets) are read directly off the ARCHETYPE dodge template inside
-- the actual dodge-execution code (player_character_state_dodging.lua),
-- with NO per-weapon override in that formula -- unlike distance/speed,
-- which the weapon template already overrides once it defines its own
-- base_distance (confirmed: weapon base_distance wins over archetype
-- base_distance whenever present, which ogryn_fast now does). This is why
-- Ogryn's dodge frequency stayed capped even after the weapon-level fix.
--
-- Directly mutating the shared archetype table (archetype_dodge_templates.
-- ogryn) was explicitly ruled out -- it would affect every Ogryn weapon,
-- not just the knife -- and it's also a single object shared by every
-- Ogryn player in a session, so temporarily mutating and restoring it
-- around the call would risk a race in multiplayer. Instead: let on_exit
-- run normally first (still handles animations, buffs, consecutive-dodge
-- counting), then overwrite the resulting PER-PLAYER cooldown fields with
-- knife-specific values -- but only when the resolved dodge template just
-- used carries the tag set above, i.e. only when a Combat Blade is
-- actually equipped. Values set aggressively low ("nearly infinite"
-- dodging, matching the user's description of how the real Combat Blade
-- plays on other classes) rather than just matching Zealot's 0.15s, since
-- this is the "over the top, confirm it first" pass.
local PlayerCharacterStateDodging =
    require("scripts/extension_systems/character_state_machine/character_states/player_character_state_dodging")
local ogryn_combatblade_dodge_cooldown = 0.05
local ogryn_combatblade_dodge_jump_override_timer = 0.05
local ogryn_combatblade_consecutive_dodges_reset = 0.1

mod:hook(PlayerCharacterStateDodging, "on_exit", function(func, self, unit, t, next_state)
    func(self, unit, t, next_state)

    local weapon_dodge_template = self._weapon_extension and self._weapon_extension:dodge_template()
    if not (weapon_dodge_template and weapon_dodge_template._bettertide_ogryn_combatblade) then
        return
    end

    local dodge_character_state_component = self._dodge_character_state_component
    local time_in_dodge = t - self._character_state_component.entered_t
    local cd = math.max(ogryn_combatblade_dodge_cooldown, ogryn_combatblade_dodge_jump_override_timer - time_in_dodge)
    dodge_character_state_component.cooldown = t + cd

    local stat_buffs = self._buff_extension:stat_buffs()
    local buff_dodge_cooldown_reset_modifier = stat_buffs.dodge_cooldown_reset_modifier or 1
    local weapon_consecutive_dodges_reset = weapon_dodge_template.consecutive_dodges_reset or 0
    local cooldown = (ogryn_combatblade_consecutive_dodges_reset + weapon_consecutive_dodges_reset)
        * buff_dodge_cooldown_reset_modifier
    dodge_character_state_component.consecutive_dodges_cooldown = t + cooldown
end)

-- action_movement_curve.modifier values are multipliers applied to the
-- character's current move speed while the heavy attack plays (confirmed
-- via WeaponActionMovement.move_speed_modifier) -- this is what produces
-- forward distance when moving + heavy-attacking together. Doubling only
-- .modifier (and .start_modifier, if present) -- .t is a normalized time
-- position (0-1) along the swing, not a magnitude, so it must stay as-is
-- or the curve's timing desyncs from the attack animation.
local function _double_movement_curve_modifiers(action_movement_curve, factor)
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
                _double_movement_curve_modifiers(action.action_movement_curve, ogryn_combatblade_mobility_multiplier)
            end
        end
    end
end

apply_ogryn_combatblade_speed_and_heavy_timing()

-- Attack speed + damage, discovered structurally rather than by a
-- hardcoded action-name list -- the 3 marks turned out to use genuinely
-- different action sets for their light-attack chains (m1/m2:
-- action_left_light/action_right_light, m2 also has a separate
-- action_light_pushfollow_combo, m3 instead uses action_light_1/2/3) and
-- different damage profile names per mark (e.g. m2 alone references
-- combat_blade_smiter_pushfollow). A hardcoded list would silently miss
-- actions on whichever mark doesn't use that exact name.
--
-- Any action with a `damage_profile` field is a real attack (verified: no
-- non-attack action -- block/push/wield/unwield/melee_start_*/inspect --
-- has this exact field; action_push has inner_damage_profile/
-- outer_damage_profile instead, a different key, so it's correctly
-- excluded). Attack speed: explicit 1.5-2x multiplier requested on top of
-- the Combat Blade's own current speed (not knife parity -- unlike dodge/
-- sprint, no comparison to the real Combat Knife was asked for here).
-- total_time is a plain number (not a *_template string), so scaling it
-- directly is safe. Runs after the heavy-timing pass above, so the two
-- heavy actions get this multiplier on top of their existing knife-parity
-- total_time (1s), not on top of vanilla Ogryn's slower 2s.
--
-- Damage: melee/special damage profiles have no ranges.min/max block
-- (that's the ranged-pellet-only shape used by the Ripper Gun below) --
-- damage is driven entirely by power_distribution.attack/.impact threshold
-- pairs, so dividing those by the multiplier raises effective damage the
-- same way lowering the Ripper Gun's bayonet-special thresholds did.
-- Every combat_blade_*-prefixed profile (and special_uppercut_plus) is
-- confirmed exclusive to this weapon family via a repo-wide search, so
-- in-place mutation is safe -- no shared-table risk, unlike stamina's
-- "default". Deduplicated by table identity across ALL 3 marks (not
-- reset per mark) since some damage profile objects are the same shared
-- table referenced by more than one mark/action -- without this, scaling
-- would compound (e.g. 2x becomes 4x) wherever that overlap happens.
local ogryn_combatblade_attack_speed_multiplier = 1.75
local ogryn_combatblade_damage_multiplier = 2
local ogryn_combatblade_scaled_damage_profiles = {}

local function apply_ogryn_combatblade_attack_speed_and_damage()
    for _, weapon_template in ipairs(ogryn_combatblade_templates) do
        for _, action in pairs(weapon_template.actions) do
            if action.damage_profile then
                action.total_time = action.total_time / ogryn_combatblade_attack_speed_multiplier

                if not ogryn_combatblade_scaled_damage_profiles[action.damage_profile] then
                    ogryn_combatblade_scaled_damage_profiles[action.damage_profile] = true
                    _scale_power_distribution_thresholds(action.damage_profile, 1 / ogryn_combatblade_damage_multiplier)
                end
            end
        end
    end
end

apply_ogryn_combatblade_attack_speed_and_damage()

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
