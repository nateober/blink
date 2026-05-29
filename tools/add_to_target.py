#!/usr/bin/env -S uv run --quiet --with pbxproj --python 3.12 --
"""Add a source file to an Xcode target's compile (Sources) phase.

Uses mod-pbxproj's low-level object API because the high-level add_file() crashes
on this project (SPM product build files lack `fileRef`). Idempotent: skips if the
file basename is already in the target's sources phase.

Usage: add_to_target.py <relative/path/to/File.swift> <TargetName>
Verify with an actual `xcodebuild build` afterwards — this does not compile.
"""
import os
import sys
from pbxproj import XcodeProject
from pbxproj.pbxsections import PBXFileReference, PBXBuildFile

def main():
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(2)
    rel, target_name = sys.argv[1], sys.argv[2]
    proj = "Blink.xcodeproj/project.pbxproj"
    p = XcodeProject.load(proj)
    target = next((t for t in p.objects.get_targets() if t.name == target_name), None)
    if target is None:
        print(f"target not found: {target_name}"); sys.exit(1)
    src = next(p.objects[pid] for pid in target.buildPhases
               if p.objects[pid].isa == "PBXSourcesBuildPhase")
    base = os.path.basename(rel)
    # idempotency: is a build file referencing this basename already present?
    for bf_id in list(src.files):
        bf = p.objects[bf_id]
        fr = p.objects.get(bf.fileRef, None) if hasattr(bf, "fileRef") else None
        if fr is not None and (getattr(fr, "name", None) == base or str(getattr(fr, "path", "")).endswith(base)):
            print(f"already present in {target_name}: {base}"); return
    fr = PBXFileReference.create(rel, tree="SOURCE_ROOT")
    fr.lastKnownFileType = "sourcecode.swift" if rel.endswith(".swift") else "sourcecode.c.objc"
    fr.name = base
    p.objects[fr.get_id()] = fr
    bf = PBXBuildFile.create(fr)
    p.objects[bf.get_id()] = bf
    src.add_build_file(bf)
    p.save()
    print(f"added {base} -> {target_name} (sources now {len(src.files)})")

if __name__ == "__main__":
    main()
