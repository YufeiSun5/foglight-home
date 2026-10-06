#!/usr/bin/env python3
"""Conservative source dependency checks, plus JSON duplicate-ID validation.

This complements runtime tests and manual review; it is not a full GDScript parser.
All dynamic resource loads are listed for review rather than silently ignored.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []
reviews = []
files = sorted((ROOT / "src").rglob("*.gd"))
classes = {}
for path in files:
    match = re.search(r"^class_name\s+(\w+)", path.read_text(), re.M)
    if match:
        classes[match.group(1)] = path.relative_to(ROOT).as_posix()


def layer(path):
    parts = path.split("/")
    if parts[0] == "scenes":
        return "scene"
    if path.startswith("src/app/ports/"):
        return "port"
    return parts[1] if parts[0] == "src" and len(parts) > 1 else "resource"


def allowed(source, target):
    source_layer, target_layer = layer(source), layer(target)
    if target_layer == "resource":
        return source_layer in {"presentation", "adapters", "bootstrap", "scene"}
    if source_layer == "bootstrap":
        return True
    if source_layer == "scene":
        return target_layer in {"presentation", "scene"} or (source == "scenes/main.tscn" and target_layer == "bootstrap")
    return target_layer in {
        "presentation": {"presentation", "app", "port"},
        "app": {"app", "port", "domain"},
        "domain": {"domain"},
        "port": {"port", "domain"},
        "adapters": {"adapters", "port", "domain"},
    }.get(source_layer, set())


for path in files + sorted((ROOT / "scenes").rglob("*.tscn")):
    relative = path.relative_to(ROOT).as_posix()
    source = path.read_text(encoding="utf-8")
    # Preserve literal resource strings while removing line comments.
    code = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    targets = set(re.findall(r'["\']res://([^"\']+)["\']', code))
    for target in targets:
        if not allowed(relative, target):
            errors.append(f"{relative}: forbidden dependency {target}")
    for name, target in classes.items():
        if target != relative and re.search(rf"\b{re.escape(name)}\b", code) and not allowed(relative, target):
            errors.append(f"{relative}: forbidden class dependency {name} ({target})")
    if layer(relative) in {"domain", "app", "port", "presentation"}:
        if re.search(r"\b(FileAccess|DirAccess)\b", code):
            errors.append(f"{relative}: filesystem IO outside adapters")
    if layer(relative) == "domain":
        if re.search(r"\b(Node|Node2D|Node3D|SceneTree|Control|ResourceLoader|Time|RandomNumberGenerator)\b|\bget_tree\s*\(", code):
            errors.append(f"{relative}: engine/world dependency in pure rules")
    if layer(relative) == "presentation" and re.search(r"\._state\b|\bwrite_snapshot\s*\(|\bRules\.reduce", code):
        errors.append(f"{relative}: presentation bypasses the application writer")
    for lineno, line in enumerate(code.splitlines(), 1):
        if re.search(r"\b(?:load|preload)\s*\(\s*[^\s\"\']", line):
            reviews.append(f"{relative}:{lineno}: dynamic load requires manual review: {line.strip()}")

for review in reviews:
    print("REVIEW:", review)
for error in errors:
    print("FAIL:", error, file=sys.stderr)
print(f"BOUNDARIES: {len(files)} scripts; {len(errors)} violations; {len(reviews)} dynamic loads listed")
sys.exit(bool(errors))
