#!/usr/bin/env python3
"""Build tileset/decor manifests from assets/tiles.

- Land And Road folders are grouped as tile sources.
- Everything else is classified as decor/props.
- Cathedral/Workshop sheets are marked for 16x16 slicing.
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TILES_ROOT = ROOT / "assets" / "tiles"
OUT_DIR = ROOT / "assets" / "tilesets" / "generated"


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        sig = f.read(8)
        if sig != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Not PNG: {path}")
        length = struct.unpack(">I", f.read(4))[0]
        chunk_type = f.read(4)
        if chunk_type != b"IHDR":
            raise ValueError(f"Invalid IHDR in: {path}")
        data = f.read(length)
        return struct.unpack(">II", data[:8])


def rel(p: Path) -> str:
    return p.relative_to(ROOT).as_posix()


def infer_land_road_tile_size(folder: Path) -> int:
    sizes = []
    for png in folder.glob("*.png"):
        w, h = png_size(png)
        if w == h and w in (32, 64):
            sizes.append(w)
    if sizes:
        return max(set(sizes), key=sizes.count)
    return 32


def build_land_and_road() -> list[dict]:
    output = []
    for folder in sorted(TILES_ROOT.rglob("Land And Road")):
        tile_size = infer_land_road_tile_size(folder)
        direct_tiles = []
        sheets = []
        for png in sorted(folder.glob("*.png")):
            w, h = png_size(png)
            entry = {"path": rel(png), "size": [w, h]}
            if w == tile_size and h == tile_size:
                direct_tiles.append(entry)
            elif w % tile_size == 0 and h % tile_size == 0:
                entry["slice_size"] = [tile_size, tile_size]
                entry["estimated_tiles"] = (w // tile_size) * (h // tile_size)
                sheets.append(entry)
            else:
                entry["warning"] = "not_divisible_by_tile_size"
                sheets.append(entry)

        output.append(
            {
                "id": rel(folder.parent).replace("/", "_").replace(" ", "_").lower(),
                "folder": rel(folder),
                "tile_size": tile_size,
                "direct_tiles": direct_tiles,
                "sheets": sheets,
                "estimated_total_tiles": len(direct_tiles)
                + sum(x.get("estimated_tiles", 0) for x in sheets),
            }
        )
    return output


def is_decor_path(path: str) -> bool:
    deco_markers = ("/decor/", "/grass/", "/stone/", "/shadow/")
    low = path.lower()
    return any(m in low for m in deco_markers)


def build_decor_props() -> dict:
    decor = []
    props = []
    for png in sorted(TILES_ROOT.rglob("*.png")):
        if "Land And Road" in png.parts:
            continue
        w, h = png_size(png)
        item = {"path": rel(png), "size": [w, h]}
        if is_decor_path(item["path"]):
            decor.append(item)
        else:
            props.append(item)

    slicing_groups = []
    for folder in [
        TILES_ROOT / "Cities And Settlements" / "Cathedral",
        TILES_ROOT / "Cities And Settlements" / "Workshop",
    ]:
        sheets = []
        for png in sorted(folder.rglob("*.png")):
            w, h = png_size(png)
            sheets.append(
                {
                    "path": rel(png),
                    "size": [w, h],
                    "slice_size": [16, 16],
                    "estimated_tiles": (w // 16) * (h // 16),
                }
            )
        slicing_groups.append(
            {
                "id": rel(folder).replace("/", "_").replace(" ", "_").lower(),
                "folder": rel(folder),
                "slice_size": [16, 16],
                "sheets": sheets,
            }
        )

    return {
        "decor": decor,
        "props": props,
        "special_sheet_slicing": slicing_groups,
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    land = build_land_and_road()
    decor_props = build_decor_props()

    (OUT_DIR / "land_and_road_tilesets.json").write_text(
        json.dumps({"tilesets": land}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (OUT_DIR / "decor_props_catalog.json").write_text(
        json.dumps(decor_props, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    summary = {
        "land_and_road_tilesets": len(land),
        "decor_count": len(decor_props["decor"]),
        "props_count": len(decor_props["props"]),
    }
    (OUT_DIR / "asset_catalog_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
