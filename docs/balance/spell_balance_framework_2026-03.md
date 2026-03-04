# Spell balance framework (2026-03) / Системный фреймворк балансировки заклинаний (2026-03)

## RU

Документ фиксирует **унифицированный подход** к балансировке классовых заклинаний, чтобы последующие проходы (шаман, паладин, охотник и т.д.) делались по одной системе.

## 1) Базовые оси баланса

Для каждой кнопки оцениваем 5 осей:

1. **Throughput** (урон/исцеление за окно времени).
2. **Tempo** (каст-тайм, кулдаун, отзывчивость).
3. **Resource pressure** (манакост/стоимость ресурса относительно регена и возврата ресурса).
4. **Utility/control value** (контроль, shield, сейв, дебаффы, групповая ценность).
5. **Role identity** (уникальность класса vs другие классы).

## 2) KPI по мане (можно применять к любому манаклассу)

- **Quick spend 12s**: сколько маны тратится в первые 12с активной ротации.
  - Рекомендуемый коридор: `5%..35%`.
- **Sustain 60s**: сколько маны остаётся после 60с непрерывной работы ротации.
  - Рекомендуемый минимум: `>=20%`.
- **Status**:
  - `OK`: spend12 <= 35% и mana60 >= 20%
  - `WARN`: spend12 <= 45% и mana60 >= 10%
  - `RISK`: всё, что хуже

Важно: KPI не заменяют плейтесты, но дают стабильную baseline-метрику.

## 3) Принципы изменения параметров

### 3.1 Resource cost
- Повышаем cost, если после бафа throughput кнопка становится «безнаказанно спамовой».
- Снижаем cost, если кнопка имеет высокий риск (длинный каст/ситуативность), но слабую практическую отдачу.
- Изменение cost обычно делаем шагами `+/-1..2` для спам-кнопок и `+/-2..4` для крупных кулдаунов.

### 3.2 Cast time
- Укорачиваем каст, когда кнопка системно проигрывает по фактическому throughput из-за времени применения.
- Удлиняем каст у слишком безопасных high-impact кнопок при отсутствии кд/ограничений.
- На high-rank избегаем резких «ломающих» ступеней, предпочитаем плавный градиент.

### 3.3 Cooldown
- Снижаем кд, если utility/aoe-кнопка «не успевает участвовать» в типичном бою.
- Повышаем кд при чрезмерном overlap-сейве/контроле, если это ломает риск профиля encounter’ов.

### 3.4 Flat/pct values
- Flat/percent бафаем в первую очередь там, где кнопка отстаёт при реальном использовании, а не только «на бумаге».
- При усилении throughput проверяем resource pressure в том же проходе.

### 3.5 Buffs/stances
- Каждая стойка/аура должна иметь ясный tradeoff (урон / защита / sustain / utility).
- Избегаем ситуаций, где один stance доминирует во всех сценариях.

## 4) Минимальный процесс для каждого следующего класса

1. Собрать текущие RankData по всем заклинаниям класса.
2. Определить 2-3 референсных профиля ротации (например: dps, heal, group-support).
3. Прогнать KPI по мане (12s/60s) на уровнях `20/40/60`.
4. Подкрутить throughput/tempo/resource как единый пакет (а не по одному параметру в отрыве).
5. Зафиксировать изменения в отдельном `docs/balance/<class>_spell_balance_pass_<date>.md`.

---

## EN

This document defines a **unified spell-balance workflow** so future class passes follow the same system.

### Core balance axes
- Throughput, tempo, resource pressure, utility/control value, role identity.

### Reusable mana KPI set
- Quick spend 12s (target `5%..35%`).
- Sustain 60s (target `>=20%` mana left).
- Status buckets: `OK / WARN / RISK`.

### Parameter tuning principles
- Adjust resource cost with throughput changes.
- Cast/cooldown tuned by practical combat value, not tooltip value only.
- Keep stance/aura tradeoffs explicit and non-dominant.

### Minimal repeatable process
- Gather rank data -> define profile rotations -> run KPI at 20/40/60 -> tune package -> document pass.
