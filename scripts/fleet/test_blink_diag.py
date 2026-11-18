import importlib.util
import json
import pathlib

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("blink_diag", HERE / "blink_diag.py")
bd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bd)

METRICS = {
    "timeStampBegin": "2026-11-12 00:00:00 +0000", "timeStampEnd": "2026-11-13 00:00:00 +0000",
    "metaData": {"appBuildVersion": "1130", "osVersion": "iPhone OS 27.2.1 (24B156)"},
    "applicationExitMetrics": {
        "foregroundExitData": {"cumulativeNormalAppExitCount": 0, "cumulativeMemoryResourceLimitExitCount": 2},
        "backgroundExitData": {"cumulativeMemoryPressureExitCount": 3, "cumulativeAppWatchdogExitCount": 1,
                               "cumulativeBadAccessExitCount": 0},
    },
    "memoryMetrics": {"peakMemoryUsage": "412,300 kB"},
}
DIAGNOSTICS = {
    "timeStampBegin": "2026-11-13 10:00:00 +0000", "timeStampEnd": "2026-11-13 10:00:00 +0000",
    "crashDiagnostics": [{"diagnosticMetaData": {"appBuildVersion": "1130", "exceptionType": 1, "signal": 11,
                                                 "terminationReason": "Namespace SIGNAL, Code 11"},
                          "callStackTree": {}}],
    "hangDiagnostics": [{"diagnosticMetaData": {"hangDuration": "4 sec"}}],
}


def test_exit_counts_drop_zeros_and_the_boilerplate():
    counts = bd.exit_counts(METRICS["applicationExitMetrics"]["backgroundExitData"])
    assert counts == {"MemoryPressure": 3, "AppWatchdog": 1}


def test_metrics_say_how_the_app_was_ended(tmp_path):
    f = tmp_path / "blink-20261113-000000-1-metrics.json"
    f.write_text(json.dumps(METRICS))
    text = "\n".join(bd.summarize_file(f))
    assert "build 1130" in text
    assert "ended in front: MemoryResourceLimit 2" in text
    assert "ended in background: AppWatchdog 1, MemoryPressure 3" in text
    assert "peak memory: 412,300 kB" in text


def test_diagnostics_list_each_crash_and_hang(tmp_path):
    f = tmp_path / "blink-20261113-100000-2-diagnostics.json"
    f.write_text(json.dumps(DIAGNOSTICS))
    text = "\n".join(bd.summarize_file(f))
    assert "crash: appBuildVersion 1130, exceptionType 1, signal 11, terminationReason Namespace SIGNAL, Code 11" in text
    assert "hang: hangDuration 4 sec" in text


def test_a_broken_file_is_named_not_fatal(tmp_path):
    f = tmp_path / "blink-x-metrics.json"
    f.write_text("{not json")
    assert "unreadable" in bd.summarize_file(f)[0]
