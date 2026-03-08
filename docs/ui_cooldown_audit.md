# UI cooldown visualization audit

Date: 2026-03-08

Scope checked:
- Mobile joystick controls (`MoveJoystick` and mobile action buttons).
- Inventory item cell visuals.
- Quick access slots (desktop quick bar and mobile skill pad).

Findings:

1. **Inventory cell (item grid): has ready cooldown fill logic.**
   - `InventoryHUD` defines `COOLDOWN_FILL_SHADER_CODE`.
   - `_ensure_slot_visuals()` creates a `ColorRect` named `Cooldown` with shader parameter `fill_pct`.
   - `_update_slot_cooldown()` updates visibility, fill percentage, and text based on consumable cooldown left.

2. **Quick access slots (desktop quick bar): has ready cooldown fill logic.**
   - `_ensure_quick_button_visuals()` creates a `Cooldown` `ColorRect` overlay with the same shader and `CooldownText`.
   - `_update_quick_cooldown()` drives `fill_pct` and countdown text from consumable cooldown.
   - `_update_visible_cooldowns()` refreshes both inventory cells and quick bar overlays.

3. **Mobile skill buttons (right-side action buttons): has ready cooldown fill logic.**
   - `SkillPad` defines `COOLDOWN_SHADER_CODE` for circular clipping + vertical fill.
   - `set_slot_cooldown()` updates `fill_pct` on `CooldownOverlay`.
   - `MobileHUD._process()` computes ability cooldown percentage via `PlayerAbilityCaster.get_cooldown_pct()` and pushes it into `SkillPad`.

4. **Movement joystick itself (left stick): no cooldown bar logic found.**
   - `MoveJoystick` only processes input/touch drag and knob positioning.
   - No cooldown shader/overlay or `fill_pct` handling there.

Conclusion:
- Cooldown visual bar/fill is already implemented for inventory item cells, desktop quick slots, and mobile skill buttons.
- The movement joystick has no cooldown visualization logic (which is expected for movement control).
