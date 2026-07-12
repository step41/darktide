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
