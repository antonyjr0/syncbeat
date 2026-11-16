"""Inventory aapt2's manifest tree, without examining application bytecode.

Usage: python scripts/zepp-manifest-inventory.py manifest-tree.txt inventory.json
Only direct application components are included, not <queries> declarations.
"""

import collections
import json
from pathlib import Path
import re
import sys


def inventory(raw):
    text = raw.decode("utf-16") if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else raw.decode("utf-8-sig")
    stack = []
    root = None
    for line in text.splitlines():
        element = re.match(r"^(\s*)E: ([\w-]+)", line)
        if element:
            depth = len(element[1])
            node = {"tag": element[2], "attrs": {}, "children": []}
            while stack and stack[-1][0] >= depth:
                stack.pop()
            if stack:
                stack[-1][1]["children"].append(node)
            else:
                root = node
            stack.append((depth, node))
            continue
        attr = re.match(r"^\s*A: (.*?)(?:\(0x[0-9a-f]+\))?=(.*)$", line)
        if attr and stack:
            key = attr[1].removeprefix("http://schemas.android.com/apk/res/android:")
            value = attr[2]
            quoted = re.search(r'\(Raw: "(.*)"\)$', value)
            value = quoted[1] if quoted else value.strip('"')
            stack[-1][1]["attrs"][key] = value
    if not root or root["tag"] != "manifest":
        raise ValueError("Expected an aapt2 dump xmltree AndroidManifest.xml")
    app = next(n for n in root["children"] if n["tag"] == "application")
    sdk = next((n["attrs"] for n in root["children"] if n["tag"] == "uses-sdk"), {})
    target = int(sdk.get("targetSdkVersion", "1"), 0)
    package = root["attrs"]["package"]

    def qualify(name):
        if name.startswith("."):
            return package + name
        return name if "." in name else package + "." + name

    components = []
    for node in app["children"]:
        if node["tag"] not in {"activity", "activity-alias", "service", "receiver", "provider"}:
            continue
        attrs = node["attrs"]
        filters = []
        for child in node["children"]:
            if child["tag"] == "intent-filter":
                filters.append({
                    "attributes": child["attrs"],
                    "actions": [n["attrs"]["name"] for n in child["children"] if n["tag"] == "action"],
                    "categories": [n["attrs"]["name"] for n in child["children"] if n["tag"] == "category"],
                    "data": [n["attrs"] for n in child["children"] if n["tag"] == "data"],
                })
        declared = attrs.get("exported")
        # Android defaults; installed target-31+ filtered components must declare it.
        default = target < 17 if node["tag"] == "provider" else bool(filters)
        exported = declared == "true" if declared is not None else default
        components.append({
            "name": qualify(attrs["name"]), "type": node["tag"],
            "exported": exported,
            "exportedSource": "explicit" if declared is not None else "Android default",
            "permission": attrs.get("permission", app["attrs"].get("permission")),
            "attributes": attrs, "intentFilters": filters,
        })
    # Alias permissions inherit from the target when not set on the alias.
    by_name = {c["name"]: c for c in components}
    for component in components:
        if component["type"] == "activity-alias" and "permission" not in component["attributes"]:
            target_component = by_name.get(qualify(component["attributes"]["targetActivity"]))
            component["permission"] = target_component["permission"] if target_component else "UNRESOLVED_TARGET"
    return {"package": package, "manifest": root["attrs"], "sdk": sdk,
            "application": app["attrs"], "counts": dict(collections.Counter(c["type"] for c in components)),
            "components": components}


if __name__ == "__main__":
    result = inventory(Path(sys.argv[1]).read_bytes())
    Path(sys.argv[2]).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"package": result["package"], "counts": result["counts"]}))
