"""Limits an .xctestrun file to one tour, for Firebase Test Lab (which runs every test in the file and has no
-only-testing option). The test bundle holds all the apps' tours; only this app's one may run.

    python3 review-tours/xctestrun.py <file.xctestrun> <TourClass>
"""
import plistlib
import sys

path, tour = sys.argv[1], sys.argv[2]
with open(path, "rb") as fh:
    data = plistlib.load(fh)


def limit(target):
    if not isinstance(target, dict) or target.get("BlueprintName", "ReviewTour") != "ReviewTour":
        return False
    target["OnlyTestIdentifiers"] = [f"{tour}/testTour"]
    target.pop("SkipTestIdentifiers", None)
    # Xcode 26 injects /usr/lib/libRPAC.dylib, which iOS 16 (the Test Lab iPhones that record video) does not
    # have: with it the app and the runner cannot start there.
    drop_rpac(target)
    return True


def drop_rpac(node):
    if isinstance(node, dict):
        if "libRPAC" in str(node.get("DYLD_INSERT_LIBRARIES", "")):
            del node["DYLD_INSERT_LIBRARIES"]
        for value in node.values():
            drop_rpac(value)
    elif isinstance(node, list):
        for value in node:
            drop_rpac(value)


changed = 0
if "TestConfigurations" in data:  # format version 2
    for config in data["TestConfigurations"]:
        for target in config.get("TestTargets", []):
            changed += limit(target)
else:  # format version 1: one top-level entry per test target
    for key, target in data.items():
        if key != "__xctestrun_metadata__" and isinstance(target, dict) and "TestBundlePath" in target:
            target.setdefault("BlueprintName", key)
            changed += limit(target)

if not changed:
    sys.exit(f"No ReviewTour test target in {path}")
with open(path, "wb") as fh:
    plistlib.dump(data, fh)
print(f"{path}: only {tour}/testTour ({changed} target)")
