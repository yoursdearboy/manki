#!/usr/bin/env python3
"""Export kept xcresult attachments and give screenshot PNGs their attachment names."""

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("xcresult", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()

raw_output = args.output.parent / f".{args.output.name}-attachments"
shutil.rmtree(raw_output, ignore_errors=True)
shutil.rmtree(args.output, ignore_errors=True)
raw_output.mkdir(parents=True)
args.output.mkdir(parents=True)

subprocess.run([
    "xcrun", "xcresulttool", "export", "attachments",
    "--path", str(args.xcresult), "--output-path", str(raw_output),
], check=True)

manifest_path = raw_output / "manifest.json"
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
renames: dict[str, str] = {}

def visit(value: object) -> None:
    if isinstance(value, dict):
        exported = value.get("exportedFileName")
        suggested = value.get("suggestedHumanReadableName")
        if isinstance(exported, str) and isinstance(suggested, str):
            renames[exported] = suggested
        for child in value.values():
            visit(child)
    elif isinstance(value, list):
        for child in value:
            visit(child)

visit(manifest)
for source in sorted(raw_output.rglob("*.png")):
    requested = renames.get(source.name, source.name)
    name = re.sub(r"[^A-Za-z0-9._-]", "-", requested)
    if not name.lower().endswith(".png"):
        name += ".png"
    destination = args.output / name
    if destination.exists():
        raise RuntimeError(f"duplicate screenshot attachment name: {name}")
    shutil.copy2(source, destination)

screenshots = list(args.output.glob("*.png"))
if not screenshots:
    raise RuntimeError("the xcresult bundle contained no PNG screenshot attachments")
print("Exported: " + ", ".join(path.name for path in screenshots))
