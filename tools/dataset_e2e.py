#!/usr/bin/env python3
"""Run a DataSetsManager-backed VINS-NEO dataset smoke test."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import Any

try:
    import resource
except ImportError:  # pragma: no cover - the runner itself is Linux-only
    resource = None


ROOT = Path(__file__).resolve().parents[1]
RESULT_NAME = "dataset-e2e-result.json"
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class E2EFailure(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def file_sha256(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def directory_sha256(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    files = sorted(item for item in path.rglob("*") if item.is_file())
    if not files:
        raise E2EFailure("artifact directory contains no files")
    for item in files:
        relative = item.relative_to(path).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        with item.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
                size += len(chunk)
    return digest.hexdigest(), size


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, indent=2, sort_keys=True, ensure_ascii=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def resolve_manifest_paths(manifest: dict[str, Any], manifest_path: Path | None) -> None:
    if manifest_path is None:
        return
    base = manifest_path.resolve().parent
    for section in ("artifact", "config"):
        value = Path(str(manifest[section]["path"]))
        if not value.is_absolute():
            manifest[section]["path"] = str((base / value).resolve())


def prepared_manifest(args: argparse.Namespace) -> tuple[dict[str, Any], Path | None]:
    if args.run_manifest:
        path = args.run_manifest.expanduser().resolve()
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise E2EFailure(f"cannot read prepared run manifest: {exc}") from exc
        resolve_manifest_paths(value, path)
        return value, path
    if args.bag or args.config:
        if not args.bag or not args.config:
            raise E2EFailure("deprecated expert override requires both --bag and --config")
        print("WARNING: --bag/--config are deprecated; use a DSM run manifest", file=sys.stderr)
        bag, config = args.bag.expanduser().resolve(), args.config.expanduser().resolve()
        artifact_sha, artifact_size = (
            directory_sha256(bag) if bag.is_dir() else file_sha256(bag)
        )
        config_sha, _ = file_sha256(config)
        return {
            "schema_version": "1.0",
            "dataset": {"id": args.dataset_id, "profile": "deprecated-expert-override"},
            "implementation": args.implementation,
            "suite": {"name": args.suite, "version": "deprecated"},
            "client": {"name": "datasetsmanager-client", "version": "deprecated"},
            "artifact": {
                "format": "rosbag2", "version": "deprecated", "sha256": artifact_sha,
                "source_sha256": artifact_sha, "size": artifact_size, "path": str(bag),
                "converted": False,
            },
            "config": {"path": str(config), "sha256": config_sha},
            "topics": {
                "camera": "/cam0/image_raw", "imu": "/imu0",
                "odometry": "/vins_estimator/odometry",
            },
            "launch": {
                "package": "vins_estimator", "file": "vins_neo.launch.py",
                "arguments": {
                    "config_file": str(config), "vins_folder": str(config.parent) + os.sep,
                    "use_sim_time": True, "log_level": "info", "logging_period_ms": 2000,
                },
            },
            "acceptance": {
                "required_topic_min_messages": {"camera": 1, "imu": 1},
                "minimum_odometry_messages": 10,
                "odometry_timestamps_monotonic": True,
                "finite_position_orientation": True,
                "processes_alive_until_bag_complete": True,
                "timeout_seconds": args.timeout or 900,
                "ground_truth_required": False,
                "delta_xy_xyz_blocking": False,
            },
        }, None
    if not args.dataset_id or not args.dsm_server_url:
        raise E2EFailure("--dataset-id and --dsm-server-url are required without --run-manifest")
    command = [
        "dsm-client", "prepare-run", args.dataset_id,
        "--implementation", args.implementation,
        "--suite", args.suite,
        "--format", "rosbag2",
        "--server-url", args.dsm_server_url,
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode:
        detail = (completed.stderr or completed.stdout or "prepare-run failed").strip()
        raise E2EFailure(f"dsm-client prepare-run failed: {detail}")
    try:
        return json.loads(completed.stdout), None
    except json.JSONDecodeError as exc:
        raise E2EFailure("dsm-client prepare-run returned invalid JSON") from exc


def validate_manifest(manifest: dict[str, Any], args: argparse.Namespace) -> tuple[Path, Path]:
    required = ("schema_version", "dataset", "implementation", "suite", "client", "artifact", "config", "topics", "launch", "acceptance")
    if manifest.get("schema_version") != "1.0" or any(key not in manifest for key in required):
        raise E2EFailure("prepared run manifest is incomplete or unsupported")
    if args.dataset_id and manifest["dataset"].get("id") != args.dataset_id:
        raise E2EFailure("prepared run dataset ID mismatch")
    if manifest.get("implementation") != args.implementation:
        raise E2EFailure("prepared run implementation mismatch")
    if manifest["suite"].get("name") != args.suite:
        raise E2EFailure("prepared run suite mismatch")
    if (
        manifest["launch"].get("package") != "vins_estimator"
        or manifest["launch"].get("file") != "vins_neo.launch.py"
    ):
        raise E2EFailure("prepared run does not use the VINS-owned combined launch")
    topics = manifest["topics"]
    if any(
        not isinstance(topics.get(name), str) or not topics[name].startswith("/")
        for name in ("camera", "imu", "odometry")
    ):
        raise E2EFailure("prepared run contains invalid ROS topics")
    acceptance = manifest["acceptance"]
    minimums = acceptance.get("required_topic_min_messages", {})
    if any(int(minimums.get(name, 0)) < 1 for name in ("camera", "imu")):
        raise E2EFailure("prepared run weakens required camera/IMU activity")
    if int(acceptance.get("minimum_odometry_messages", 0)) < 10:
        raise E2EFailure("prepared run weakens the 10-message odometry minimum")
    for requirement in (
        "odometry_timestamps_monotonic",
        "finite_position_orientation",
        "processes_alive_until_bag_complete",
    ):
        if acceptance.get(requirement) is not True:
            raise E2EFailure(f"prepared run disables mandatory acceptance: {requirement}")
    for section in ("artifact", "config"):
        if not SHA256.fullmatch(str(manifest[section].get("sha256", ""))):
            raise E2EFailure(f"prepared run has invalid {section} SHA-256")
    artifact = Path(str(manifest["artifact"]["path"])).resolve()
    config = Path(str(manifest["config"]["path"])).resolve()
    if not artifact.exists() or not config.is_file():
        raise E2EFailure("prepared artifact or config is missing")
    actual_artifact_sha, actual_size = (
        directory_sha256(artifact) if artifact.is_dir() else file_sha256(artifact)
    )
    if actual_artifact_sha != manifest["artifact"].get("sha256"):
        raise E2EFailure("artifact checksum mismatch before VINS launch")
    if not artifact.is_dir() and actual_size <= 64:
        raise E2EFailure("fixture-sized artifact is forbidden for real e2e")
    config_sha, _ = file_sha256(config)
    if config_sha != manifest["config"].get("sha256"):
        raise E2EFailure("config checksum mismatch before VINS launch")
    return artifact, config


def cleanup_process(
    process: subprocess.Popen | None,
    grace: float = 5.0,
    launch_parent: bool = False,
) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        # ROS launch forwards SIGINT to its children. Signalling its process
        # group would deliver SIGINT to the nodes twice and can corrupt DDS
        # teardown. Other isolated subprocesses can receive the group signal.
        if launch_parent:
            process.send_signal(signal.SIGINT)
        else:
            os.killpg(process.pid, signal.SIGINT)
        process.wait(timeout=grace)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=grace)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=grace)


def sanitize(text: str, replacements: list[Path], token: str | None = None) -> str:
    result = text
    for path in sorted({str(item.resolve()) for item in replacements}, key=len, reverse=True):
        result = re.sub(re.escape(path), "<PRIVATE_PATH>", result, flags=re.IGNORECASE)
    if token:
        result = result.replace(token, "<REDACTED_TOKEN>")
    return result


def write_sanitized(source: Path, destination: Path, replacements: list[Path]) -> None:
    if source.is_file():
        text = source.read_text(encoding="utf-8", errors="replace")
        destination.write_text(
            sanitize(text, replacements, os.environ.get("DSM_SERVER_TOKEN")),
            encoding="utf-8", newline="\n",
        )


def bag_topics(info: str) -> dict[str, dict[str, Any]]:
    topics: dict[str, dict[str, Any]] = {}
    pattern = re.compile(r"Topic:\s*(\S+)\s*\|\s*Type:\s*(\S+)\s*\|\s*Count:\s*(\d+)")
    for match in pattern.finditer(info):
        topics[match.group(1)] = {"type": match.group(2), "count": int(match.group(3))}
    return topics


def node_list() -> tuple[int, str]:
    completed = subprocess.run(["ros2", "node", "list"], capture_output=True, text=True, check=False)
    return completed.returncode, completed.stdout


def wait_for_nodes(launch: subprocess.Popen, timeout_seconds: int = 30) -> str:
    deadline = time.monotonic() + timeout_seconds
    latest = ""
    required = {"/feature_tracker/feature_tracker", "/vins_estimator/vins_estimator"}
    while time.monotonic() < deadline:
        if launch.poll() is not None:
            raise E2EFailure("VINS launch exited before nodes became ready")
        status, latest = node_list()
        if status == 0 and required.issubset(set(latest.splitlines())):
            return latest
        time.sleep(1)
    raise E2EFailure("VINS nodes did not become ready within 30 seconds")


def evidence_class() -> str:
    os_release = Path("/etc/os-release").read_text(encoding="utf-8", errors="replace") if Path("/etc/os-release").is_file() else ""
    native_arm64 = platform.machine() in {"aarch64", "arm64"}
    debian13 = bool(re.search(r'^VERSION_ID=["\']?13["\']?$', os_release, re.MULTILINE))
    return "release" if native_arm64 and debian13 and not Path("/.dockerenv").exists() else "development"


def run(args: argparse.Namespace) -> int:
    evidence = args.evidence_dir.expanduser().resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    result_path = evidence / RESULT_NAME
    started = now()
    result: dict[str, Any] = {
        "schema_version": "1.0",
        "status": "FAIL",
        "reason": "runner did not complete",
        "started_at": started,
        "finished_at": None,
        "evidence_class": evidence_class(),
        "inputs": {},
        "checks": {},
        "measurements": {},
    }
    launch = monitor = playback = None
    launch_stream = playback_stream = None
    replacements = [evidence]
    temporary_root = Path(tempfile.mkdtemp(prefix="vins-dataset-e2e-"))
    replacements.append(temporary_root)
    launch_log = temporary_root / "vins-launch.log"
    playback_log = temporary_root / "bag-play.log"
    monitor_output = temporary_root / "monitor.json"
    bag_info_file = temporary_root / "bag-info.txt"
    nodes_file = temporary_root / "nodes.txt"
    try:
        manifest, manifest_path = prepared_manifest(args)
        artifact, config = validate_manifest(manifest, args)
        replacements.extend(
            path for path in (artifact, config, artifact.parent, config.parent)
            if path != Path(path.anchor)
        )
        topics = manifest["topics"]
        acceptance = manifest["acceptance"]
        result["inputs"] = {
            "dataset_id": manifest["dataset"]["id"],
            "profile": manifest["dataset"]["profile"],
            "implementation": manifest["implementation"],
            "artifact_format": manifest["artifact"]["format"],
            "artifact_version": manifest["artifact"]["version"],
            "artifact_sha256": manifest["artifact"]["sha256"],
            "artifact_source_sha256": manifest["artifact"].get("source_sha256"),
            "config_sha256": manifest["config"]["sha256"],
            "suite": manifest["suite"]["name"],
            "suite_version": manifest["suite"]["version"],
            "dsm_client_version": manifest["client"]["version"],
        }
        info = subprocess.run(
            ["ros2", "bag", "info", str(artifact)], capture_output=True, text=True,
            check=False, timeout=60,
        )
        bag_info_file.write_text(info.stdout + info.stderr, encoding="utf-8")
        if info.returncode:
            raise E2EFailure("artifact does not pass ros2 bag info")
        inventory = bag_topics(info.stdout)
        expected_types = {"camera": "sensor_msgs/msg/Image", "imu": "sensor_msgs/msg/Imu"}
        bag_counts: dict[str, int] = {}
        for key in ("camera", "imu"):
            topic = topics[key]
            item = inventory.get(topic)
            if not item:
                raise E2EFailure(f"required bag topic is missing: {topic}")
            if item["type"] != expected_types[key]:
                raise E2EFailure(f"bag topic has wrong type: {topic} ({item['type']})")
            if item["count"] < int(acceptance["required_topic_min_messages"][key]):
                raise E2EFailure(f"required bag topic has no usable messages: {topic}")
            bag_counts[key] = item["count"]
        result["checks"]["bag_info"] = "PASS"
        result["measurements"]["bag_message_counts"] = bag_counts

        launch_arguments = dict(manifest["launch"]["arguments"])
        launch_arguments["config_file"] = str(config)
        launch_arguments["vins_folder"] = str(config.parent) + os.sep
        launch_command = [
            "ros2", "launch", manifest["launch"]["package"], manifest["launch"]["file"],
            *[
                f"{key}:={str(value).lower() if isinstance(value, bool) else value}"
                for key, value in launch_arguments.items()
            ],
        ]
        launch_stream = launch_log.open("w", encoding="utf-8")
        launch = subprocess.Popen(
            launch_command, stdout=launch_stream, stderr=subprocess.STDOUT,
            text=True, start_new_session=True,
        )
        ready_nodes = wait_for_nodes(launch)
        nodes_file.write_text(ready_nodes, encoding="utf-8")
        result["checks"]["nodes_ready"] = "PASS"

        monitor_command = [
            sys.executable, str(ROOT / "tools/dataset_e2e_monitor.py"),
            "--camera-topic", topics["camera"], "--imu-topic", topics["imu"],
            "--odometry-topic", topics["odometry"], "--output", str(monitor_output),
        ]
        monitor = subprocess.Popen(
            monitor_command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        time.sleep(1)
        if monitor.poll() is not None:
            raise E2EFailure("runtime topic monitor exited before bag playback")

        playback_stream = playback_log.open("w", encoding="utf-8")
        playback = subprocess.Popen(
            ["ros2", "bag", "play", str(artifact), "--clock"],
            stdout=playback_stream, stderr=subprocess.STDOUT, text=True,
            start_new_session=True,
        )
        deadline = time.monotonic() + int(args.timeout or acceptance["timeout_seconds"])
        while playback.poll() is None:
            if time.monotonic() >= deadline:
                raise E2EFailure("dataset playback timeout")
            if launch.poll() is not None:
                raise E2EFailure("VINS launch exited before bag completion")
            if monitor.poll() is not None:
                raise E2EFailure("runtime topic monitor exited before bag completion")
            time.sleep(0.25)
        playback_stream.close()
        if playback.returncode:
            raise E2EFailure(f"ros2 bag play failed with exit code {playback.returncode}")
        if launch.poll() is not None:
            raise E2EFailure("VINS launch was not alive at bag completion")
        status, final_nodes = node_list()
        required_nodes = {"/feature_tracker/feature_tracker", "/vins_estimator/vins_estimator"}
        if status or not required_nodes.issubset(set(final_nodes.splitlines())):
            raise E2EFailure("one or both VINS nodes were absent at bag completion")
        nodes_file.write_text(ready_nodes + "\n--- bag complete ---\n" + final_nodes, encoding="utf-8")
        result["checks"]["process_liveness"] = "PASS"

        time.sleep(2)
        cleanup_process(monitor)
        if not monitor_output.is_file():
            raise E2EFailure("runtime topic monitor produced no result")
        measurements = json.loads(monitor_output.read_text(encoding="utf-8"))
        counts = measurements["counts"]
        for key in ("camera", "imu"):
            if counts[key] < int(acceptance["required_topic_min_messages"][key]):
                raise E2EFailure(f"no runtime activity on {topics[key]}")
        if counts["odometry"] < int(acceptance["minimum_odometry_messages"]):
            raise E2EFailure(
                f"odometry count {counts['odometry']} is below {acceptance['minimum_odometry_messages']}"
            )
        if acceptance["odometry_timestamps_monotonic"] and not measurements["odometry_timestamps_monotonic"]:
            raise E2EFailure("odometry timestamps are not monotonic")
        if acceptance["finite_position_orientation"] and not measurements["odometry_finite"]:
            raise E2EFailure("odometry position/orientation contains non-finite values")
        result["checks"].update({
            "runtime_topic_activity": "PASS",
            "odometry_count": "PASS",
            "odometry_timestamps": "PASS",
            "odometry_finite": "PASS",
        })
        result["measurements"].update(measurements)
        result["status"] = "PASS"
        result["reason"] = "all dataset smoke acceptance checks passed"
        return 0
    except KeyboardInterrupt:
        result["reason"] = "interrupted"
        return 1
    except (E2EFailure, subprocess.TimeoutExpired, OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        result["reason"] = sanitize(
            str(exc), replacements, os.environ.get("DSM_SERVER_TOKEN")
        )
        return 1
    finally:
        cleanup_process(playback)
        cleanup_process(monitor)
        cleanup_process(launch, launch_parent=True)
        for stream in (playback_stream, launch_stream):
            if stream is not None and not stream.closed:
                stream.close()
        if resource is not None:
            usage = resource.getrusage(resource.RUSAGE_CHILDREN)
            result["measurements"]["cpu_user_seconds"] = usage.ru_utime
            result["measurements"]["cpu_system_seconds"] = usage.ru_stime
            result["measurements"]["peak_rss_kib"] = usage.ru_maxrss
        result["finished_at"] = now()
        write_sanitized(bag_info_file, evidence / "bag-info.txt", replacements)
        write_sanitized(launch_log, evidence / "vins-launch.log", replacements)
        write_sanitized(playback_log, evidence / "bag-play.log", replacements)
        write_sanitized(nodes_file, evidence / "nodes.txt", replacements)
        atomic_json(result_path, result)
        shutil.rmtree(temporary_root, ignore_errors=True)


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--dataset-id")
    value.add_argument("--suite", default="smoke")
    value.add_argument("--implementation", default="vins-neo")
    value.add_argument("--dsm-server-url")
    value.add_argument("--evidence-dir", type=Path, required=True)
    value.add_argument("--run-manifest", type=Path, help="prepared tokenless host-to-Pi input")
    value.add_argument("--timeout", type=int)
    value.add_argument("--bag", type=Path, help="deprecated expert override")
    value.add_argument("--config", type=Path, help="deprecated expert override")
    return value


def main() -> int:
    return run(parser().parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
