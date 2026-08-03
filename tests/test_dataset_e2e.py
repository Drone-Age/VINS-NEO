"""Static and pure-Python contracts for the VINS-owned dataset runner."""

import importlib.util
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("dataset_e2e", ROOT / "tools/dataset_e2e.py")
E2E = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(E2E)


class DatasetE2EContractTest(unittest.TestCase):
    def test_runner_exposes_dsm_and_tokenless_pi_inputs(self):
        runner = (ROOT / "tools/dataset_e2e.py").read_text(encoding="utf-8")
        for argument in (
            "--dataset-id", "--suite", "--dsm-server-url", "--evidence-dir",
            "--run-manifest",
        ):
            self.assertIn(argument, runner)
        self.assertIn('"dsm-client", "prepare-run"', runner)
        self.assertNotIn('"--allow-test-fixture"', runner)

    def test_result_and_cleanup_contract_is_explicit(self):
        runner = (ROOT / "tools/dataset_e2e.py").read_text(encoding="utf-8")
        for field in (
            "artifact_version", "artifact_sha256", "artifact_source_sha256",
            "config_sha256", "suite_version", "dsm_client_version",
            "cpu_user_seconds", "peak_rss_kib", "evidence_class",
        ):
            self.assertIn(field, runner)
        self.assertIn("os.killpg", runner)
        self.assertIn("process.send_signal(signal.SIGINT)", runner)
        self.assertIn("cleanup_process(launch, launch_parent=True)", runner)
        self.assertIn("finally:", runner)
        self.assertIn("dataset-e2e-result.json", runner)
        estimator = (ROOT / "vins_estimator/src/estimator_node.cpp").read_text(
            encoding="utf-8"
        )
        self.assertIn("while (rclcpp::ok())", estimator)
        self.assertIn("con.notify_all();", estimator)
        self.assertIn("measurement_process.join();", estimator)
        self.assertIn("unregisterPub();", estimator)
        tracker = (ROOT / "feature_tracker/src/feature_tracker_node.cpp").read_text(
            encoding="utf-8"
        )
        self.assertIn("pub_img.reset();", tracker)

    def test_hash_and_log_sanitization_are_deterministic(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private = root / "private"
            private.mkdir()
            (private / "a").write_bytes(b"a")
            (private / "b").write_bytes(b"b")
            first = E2E.directory_sha256(private)
            second = E2E.directory_sha256(private)
            self.assertEqual(first, second)
            sanitized = E2E.sanitize(f"path={private} token=secret", [private], "secret")
            self.assertNotIn(str(private), sanitized)
            self.assertNotIn("secret", sanitized)

    def test_monitor_checks_counts_monotonicity_finiteness_and_deltas(self):
        monitor = (ROOT / "tools/dataset_e2e_monitor.py").read_text(encoding="utf-8")
        for token in (
            '"camera": 0', '"imu": 0', '"odometry": 0',
            "odometry_monotonic", "math.isfinite", '"xy"', '"xyz"',
        ):
            self.assertIn(token, monitor)

    def test_manifest_cannot_weaken_vins_owned_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root / "bag"
            artifact.mkdir()
            (artifact / "metadata.yaml").write_text("rosbag2_bagfile_information: {}")
            config = root / "config.yaml"
            config.write_text("config: fixture")
            artifact_sha, _ = E2E.directory_sha256(artifact)
            config_sha = hashlib.sha256(config.read_bytes()).hexdigest()
            manifest = {
                "schema_version": "1.0",
                "dataset": {"id": "iv.dev.4.ff.1", "profile": "dev_04"},
                "implementation": "vins-neo",
                "suite": {"name": "smoke", "version": "1.0.0"},
                "client": {"name": "datasetsmanager-client", "version": "1.1.0"},
                "artifact": {"path": str(artifact), "sha256": artifact_sha},
                "config": {"path": str(config), "sha256": config_sha},
                "topics": {
                    "camera": "/cam0/image_raw", "imu": "/imu0",
                    "odometry": "/vins_estimator/odometry",
                },
                "launch": {"package": "vins_estimator", "file": "vins_neo.launch.py"},
                "acceptance": {
                    "required_topic_min_messages": {"camera": 1, "imu": 1},
                    "minimum_odometry_messages": 9,
                    "odometry_timestamps_monotonic": True,
                    "finite_position_orientation": True,
                    "processes_alive_until_bag_complete": True,
                },
            }
            args = argparse.Namespace(
                dataset_id="iv.dev.4.ff.1", implementation="vins-neo", suite="smoke"
            )
            with self.assertRaisesRegex(E2E.E2EFailure, "10-message"):
                E2E.validate_manifest(manifest, args)


if __name__ == "__main__":
    unittest.main()
