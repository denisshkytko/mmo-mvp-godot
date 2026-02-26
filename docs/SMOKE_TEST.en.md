# SMOKE TEST (manual checklist)

Russian version: `docs/SMOKE_TEST.md`.

Use this checklist for quick verification after structural/path changes.

1. **Project startup**
   - Open project in Godot.
   - Ensure no missing resource errors in output.

2. **Flow screens**
   - Login screen opens.
   - Character selection opens after login.

3. **Enter game world**
   - `Main.tscn` loads successfully.
   - `GameUI` is visible and no missing scene/script warnings appear.

4. **HUD checks**
   - Core HUD blocks render (player/target/xp/buffs).
   - Window HUDs open/close (inventory/character/menu/merchant/loot).
   - Trainer/mobile/combat-text modules initialize without path errors.

5. **Tooltip and overlays**
   - Ability tooltip appears and hides correctly.

6. **Abilities data**
   - Ability DB initializes and loads abilities from manifest.
   - Ability descriptions render using a single `description` field.

7. **Regression quick pass**
   - Basic combat interaction works.
   - No runtime errors related to moved files/paths.
