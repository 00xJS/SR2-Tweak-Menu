"""Read SR2's active GML1.xtbl and emit the fitting room's clip catalog."""
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


def build(table, output):
    root = ET.parse(table).getroot()
    locomotion = {"walk", "run", "jog", "sprint", "crouch", "crouch walk"}
    stances = {"stand ready", "fine aim stand", "crouch ready", "stand ready left", "stand ready right"}
    melee_groups = {"h1h", "h2h", "h2hl", "h2hh", "nightstick", "knife", "pimpslap", "pimp", "chainsaw"}
    catalog = {"Locomotion": {}, "Combat Stances": {}, "Melee": {}}
    for group in root.findall("./Table/Skeleton_Set/Groups/Group"):
        weapon = group.findtext("group")
        key = weapon.lower()
        for state in group.findall("./States/State"):
            name = state.findtext("ID")
            if key == "default" and name.lower() in locomotion:
                family = "Locomotion"
            elif name.lower() in stances:
                family = "Combat Stances"
            else:
                continue
            add(catalog[family], weapon, state, name)
        if key == "default" or key.startswith(("melee", "sword_")) or key in melee_groups:
            for action in group.findall("./Actions/Action"):
                name = action.findtext("ID")
                if key != "default" or any(word in name.lower() for word in ("melee", "punch", "kick")):
                    add(catalog["Melee"], weapon, action, name)

    lines = ["-- Generated from GML1.xtbl by tools/build_movement_previews.py.", "return {"]
    for category, weapons in catalog.items():
        lines.append(f"  {{ {json.dumps(category)}, {{")
        for weapon, entries in weapons.items():
            lines.append(f"    {{ {json.dumps(weapon)}, {{")
            for label, clip in entries:
                lines.append(f"      {{ {json.dumps(label)}, {json.dumps(clip)} }},")
            lines.append("    } },")
        lines.append("  } },")
    lines.append("}")
    Path(output).write_text("\n".join(lines) + "\n", encoding="utf-8")


def add(groups, weapon, node, name):
    filename = node.findtext("Animation/Filename")
    if filename:
        pair = (name, filename.lower().removesuffix(".animx"))
        entries = groups.setdefault(weapon, [])
        if pair not in entries:
            entries.append(pair)


if __name__ == "__main__":
    build(*sys.argv[1:])
