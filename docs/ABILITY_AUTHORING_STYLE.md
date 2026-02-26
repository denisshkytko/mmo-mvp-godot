# Ability Authoring Style (Class-agnostic)

This document fixes a single authoring style for all class abilities (`.tres`) based on the current paladin/shaman setup.

## 1) Resource structure
Each ability should be authored as one `AbilityDefinition` resource:
- script: `res://core/abilities/ability_definition.gd`
- rank blocks: `RankData` subresources
- effect block(s): typed effect subresources (e.g. `EffectDamage`, `EffectHeal`, `EffectMixedDamage`)

Use the same section order as existing class files:
1. `[gd_resource ...]`
2. `[ext_resource ...]`
3. `[sub_resource RankData ...]` (all ranks)
4. `[sub_resource Effect... ...]`
5. `[resource]` (`id`, `name`, `icon`, descriptions, targeting, effect, ranks)

## 2) Localization during interim phase
Until external localization storage is introduced:
- keep a single `description` field in the `.tres` and use placeholders for dynamic values.
- do not create separate RU/ENG files for one ability.

## 3) Tooltip template tokens
Use the following placeholders in `description` whenever possible:
- `{X}`  : primary flat value (tooltip uses scaled flat)
- `{X2}` : secondary flat value (raw `value_flat_2`)
- `{M}`  : magic/secondary scaled flat
- `{P}`  : primary percent (`value_pct`)
- `{P2}` : secondary percent (`value_pct_2`)
- `{T}`  : threshold percent (mapped to `value_pct`)
- `{HP}` : health percent (`value_pct`)
- `{MP}` : mana percent (`value_pct_2`)
- `{D}`  : duration in seconds

## 4) Stance/Aura payload conventions
- For stance-driven threat scaling, use `on_hit.threat_multiplier` in buff data.
- Example: `on_hit = {"threat_multiplier": "value_pct"}` with rank `value_pct = 5` for x5 threat.
- For flat primary-stat buffs (STR/AGI/END/INT/PER), use `primary_add` (not `secondary_add`).
- Example: `primary_add = {"agi": "value_flat", "per": "value_flat"}`.

## 5) Progression and training cost
- rank required levels and rank values come from game design for each spell.
- `train_cost_gold` should follow the established level->cost trainer curve used in existing abilities.

## 6) Manifest wiring
Every new ability must be registered in:
- `core/data/abilities/abilities_manifest.tres`

## 7) Icons
- icon filename: snake_case based on ability name.
- icon path: `assets/icons/abilities/<class_id>/<ability_id>.png`
- bind icon via `icon = ExtResource(...)` when asset is present in repo.

- For negative status effects use `EffectApplyDebuff` (same payload as buff + `is_debuff=true`) and keep debuffs in the same snapshot stream so HUD/TargetHUD can split them visually.
