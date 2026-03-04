# Spell power scaling framework (2026-03) / Фреймворк скейлинга от силы заклинаний (2026-03)

## RU

Этот документ фиксирует единые правила скейлинга силы заклинаний (SP), чтобы:
- длинные заклинания получали больший вклад от SP,
- быстрые/мгновенные кнопки не доминировали по эффективности,
- direct / DoT / heal имели разные кривые усиления.

## 1) Категории и коэффициенты

Коэффициенты задаются в процентах от текущей силы заклинаний и применяются к `spell_power` как бонус к `value_flat`.

### 1.1 Direct damage
По `cast_time_sec`:
- `>= 2.5s` -> `100%`
- `1.5..2.49s` -> `80%`
- `0.5..1.49s` -> `60%`
- `< 0.5s` -> `40%`

### 1.2 DoT
По `cast_time_sec`:
- `>= 2.5s` -> `70%`
- `1.5..2.49s` -> `60%`
- `0.5..1.49s` -> `50%`
- `< 0.5s` -> `40%`

### 1.3 Direct heal
По `cast_time_sec`:
- `>= 2.5s` -> `95%`
- `1.5..2.49s` -> `80%`
- `0.5..1.49s` -> `65%`
- `< 0.5s` -> `50%`

### 1.4 HoT
По `cast_time_sec`:
- `>= 2.5s` -> `85%`
- `1.5..2.49s` -> `75%`
- `0.5..1.49s` -> `60%`
- `< 0.5s` -> `50%`

## 2) Правила применения

- Формула бонуса: `sp_bonus = round(spell_power * coeff_pct / 100)`.
- Итоговая база способности: `value_flat + sp_bonus`.
- Для DoT/HoT бонус применяется через специализированные токены в бафф-резолвере:
  - `caster_spell_power_dot`
  - `caster_spell_power_hot`
- Для прямого урона/исцеления коэффициент применяется в effect-скриптах через общую утилиту.

## 3) Overrides

Для точечной настройки конкретных рангов используется `RankData.flags`:
- `sp_coeff_direct_pct`
- `sp_coeff_dot_pct`
- `sp_coeff_heal_pct`
- `sp_coeff_hot_pct`

Если override отсутствует, используется базовая таблица по времени каста.

## 4) Принцип безопасного rollout

1. Внедрить общую механику коэффициентов в эффект-скрипты и tooltip-расчёт.
2. Прогнать KPI-аудит и плейтесты.
3. Компенсировать `value_flat`/`resource_cost` там, где фактическая отдача упала сверх целевого коридора.

---

## EN

This document defines a unified SP scaling policy so that long casts gain more from SP, while fast/instant buttons remain controlled.

### Categories
- Direct damage: `100/80/60/40` by cast-time bucket.
- DoT: `70/60/50/40` by cast-time bucket.
- Direct heal: `95/80/65/50` by cast-time bucket.
- HoT: `85/75/60/50` by cast-time bucket.

### Formula
`sp_bonus = round(spell_power * coeff_pct / 100)`, then `base = value_flat + sp_bonus`.

### Overrides
Use `RankData.flags` keys:
- `sp_coeff_direct_pct`, `sp_coeff_dot_pct`, `sp_coeff_heal_pct`, `sp_coeff_hot_pct`.
