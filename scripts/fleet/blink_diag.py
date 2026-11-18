#!/usr/bin/env python3
"""blink-diag: read the reports Blink uploads about itself (iOS MetricKit) from
~/Scratch/blink-diag/ and say why the app was ended.

  blink-diag            a summary of every report, oldest first
  blink-diag --days N   only reports from the last N days
  blink-diag FILE...    summarize these files

Standard library only.
"""
import json
import re
import sys
import time
from pathlib import Path

DIR = Path.home() / "Scratch" / "blink-diag"


def exit_counts(section):
    """{"MemoryResourceLimit": 2, ...} from one of MetricKit's exit-data dictionaries,
    leaving out the zeros."""
    out = {}
    for key, value in (section or {}).items():
        if not isinstance(value, int) or value == 0:
            continue
        name = re.sub(r"^cumulative", "", key)
        name = re.sub(r"(Exit)?Count$", "", name)
        out[name or key] = value
    return out


def summarize_metrics(data):
    lines = []
    # MetricKit's JSON puts the build under metaData (seen in the phone's reports, 2026-11).
    meta = data.get("metaData") or data.get("metaInformation") or {}
    build = (meta.get("appBuildVersion") or meta.get("applicationBuildVersion")
             or data.get("appBuildVersion") or "?")
    span = f"{data.get('timeStampBegin', '?')} to {data.get('timeStampEnd', '?')}"
    lines.append(f"metrics, build {build}, {span}")
    exits = data.get("applicationExitMetrics") or {}
    for label, key in (("in front", "foregroundExitData"), ("in background", "backgroundExitData")):
        counts = exit_counts(exits.get(key))
        if counts:
            text = ", ".join(f"{name} {count}" for name, count in sorted(counts.items()))
            lines.append(f"  ended {label}: {text}")
    memory = (data.get("memoryMetrics") or {}).get("peakMemoryUsage")
    if memory:
        lines.append(f"  peak memory: {memory}")
    return lines


def summarize_diagnostics(data):
    lines = []
    span = f"{data.get('timeStampBegin', '?')} to {data.get('timeStampEnd', '?')}"
    lines.append(f"diagnostics, {span}")
    for key, value in sorted(data.items()):
        if not key.endswith("Diagnostics") or not isinstance(value, list):
            continue
        kind = key[: -len("Diagnostics")]
        for item in value:
            meta = item.get("diagnosticMetaData") or {}
            wanted = ("appBuildVersion", "exceptionType", "exceptionCode", "signal",
                      "terminationReason", "hangDuration", "totalCPUTime", "virtualMemoryRegionInfo")
            text = ", ".join(f"{name} {meta[name]}" for name in wanted if name in meta)
            lines.append(f"  {kind}: {text or 'no details'}")
    if len(lines) == 1:
        lines.append("  nothing reported")
    return lines


def summarize_file(path):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError) as e:
        return [f"{Path(path).name}: unreadable ({e})"]
    body = summarize_diagnostics(data) if str(path).endswith("-diagnostics.json") else summarize_metrics(data)
    return [f"{Path(path).name}"] + ["  " + line for line in body]


def main(argv):
    days = None
    if argv[:1] == ["--days"] and len(argv) >= 2 and argv[1].isdigit():
        days, argv = int(argv[1]), argv[2:]
    files = [Path(a) for a in argv] or sorted(DIR.glob("blink-*.json"))
    if days is not None:
        cutoff = time.time() - days * 86400
        files = [f for f in files if f.exists() and f.stat().st_mtime >= cutoff]
    if not files:
        print(f"no reports in {DIR} yet (iOS hands them to the app about once a day, and after a crash)")
        return 0
    for f in files:
        print("\n".join(summarize_file(f)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
