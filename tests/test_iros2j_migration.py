import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def parse_manifest(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    return values


class Iros2jMigrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = parse_manifest(
            ROOT / "config" / "releases" / "v1_00_03_00.env"
        )
        cls.native = (ROOT / "tools" / "native-release.sh").read_text(
            encoding="utf-8"
        )
        cls.dispatcher = (
            ROOT / "tools" / "invoke-native-release.ps1"
        ).read_text(encoding="utf-8")

    def test_exact_runtime_identity(self) -> None:
        self.assertEqual(self.manifest["MANIFEST_SCHEMA"], "3")
        self.assertEqual(self.manifest["IROS_NAME"], "iros2j")
        self.assertEqual(self.manifest["IROS_VERSION"], "1.0.3")
        self.assertEqual(
            self.manifest["IROS_DEB_VERSION"], "1.0.3-1+deb13"
        )
        self.assertEqual(self.manifest["IROS_PREFIX"], "/opt/iros2j")
        self.assertEqual(self.manifest["IMAVROS_VERSION"], "1.0.0.2")
        self.assertEqual(self.manifest["IMAVROS_PREFIX"], "/opt/imavros")
        self.assertIn(
            '$manifest["MANIFEST_SCHEMA"] -notin @("2", "3")',
            self.dispatcher,
        )

    def test_iros2j_dependency_closure_is_exact_and_sorted(self) -> None:
        packages = self.manifest["IROS_PACKAGES"].split(",")
        self.assertEqual(packages, sorted(set(packages)))
        self.assertIn("iros2j-cv-bridge", packages)
        self.assertIn("iros2j-image-transport", packages)
        self.assertIn("iros2j-rmw-fastrtps-cpp", packages)
        self.assertIn("iros2j-ament-lint-auto", packages)
        self.assertIn("iros2j-ament-lint-common", packages)
        self.assertTrue(all(name.startswith("iros2j-") for name in packages))
        runtime = self.manifest["IROS_RUNTIME_PACKAGES"].split(",")
        self.assertEqual(runtime, sorted(set(runtime)))
        self.assertTrue(set(runtime) < set(packages))
        self.assertNotIn("iros2j-ament-cmake", runtime)

    def test_private_cv_bridge_build_is_removed(self) -> None:
        forbidden = (
            "--cv-bridge-ref",
            "CV_BRIDGE_REF",
            "vision_opencv.git",
            "cv_bridge-build",
            'step "Build pinned cv_bridge"',
        )
        for token in forbidden:
            self.assertNotIn(token, self.native)
            self.assertNotIn(token, self.dispatcher)

    def test_active_runtime_paths_use_iros2j(self) -> None:
        self.assertIn("source_setup /opt/iros2j/setup.bash", self.native)
        self.assertIn("[ -f /opt/iros2j/setup.sh ]", self.native)
        self.assertIn("source '$imavros_prefix/setup.bash'", self.native)
        self.assertIn("source /opt/vins/setup.bash", self.native)

    def test_package_audit_rejects_legacy_and_duplicate_payload(self) -> None:
        self.assertIn('fail "Obsolete iros2-0 is installed"', self.native)
        self.assertIn('fail "Obsolete /opt/iros2_0 prefix exists"', self.native)
        self.assertIn(
            'fail "/opt/vins contains a private cv_bridge payload"',
            self.native,
        )
        self.assertIn(
            'fail "$ros_package resolves to $package_prefix, not /opt/iros2j"',
            self.native,
        )

    def test_current_normative_documents_are_paired(self) -> None:
        pairs = (
            ("docs/RELEASE_PROCESS.md", "docs/RELEASE_PROCESS.uk.md"),
            ("docs/PRE_RELEASE_TESTING.md", "docs/PRE_RELEASE_TESTING.uk.md"),
            ("docs/DATASET_E2E.md", "docs/DATASET_E2E.uk.md"),
            ("docs/AMD64_TEST_RELEASE.md", "docs/AMD64_TEST_RELEASE.uk.md"),
            ("config/native/README.md", "config/native/README.uk.md"),
            ("config/releases/README.md", "config/releases/README.uk.md"),
        )
        for english, ukrainian in pairs:
            self.assertTrue((ROOT / english).is_file(), english)
            self.assertTrue((ROOT / ukrainian).is_file(), ukrainian)
        for english, ukrainian in pairs:
            if "AMD64_TEST_RELEASE" in english:
                continue
            for path in (english, ukrainian):
                text = (ROOT / path).read_text(encoding="utf-8")
                self.assertIn("iros2j", text)
                self.assertIn("/opt/iros2j", text)

    def test_process_version_records_contract_change(self) -> None:
        self.assertEqual(
            (ROOT / "PROCESS_VERSION").read_text(encoding="utf-8").strip(),
            "1.3.0",
        )
        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn("## Process [1.3.0] - Unreleased", changelog)

    def test_native_gate_emits_structured_results(self) -> None:
        for field in (
            "test_id",
            "result",
            "started_at",
            "finished_at",
            "host",
            "target",
            "command",
            "evidence",
            "reason",
            "missing_component",
            "requirement_effect",
        ):
            self.assertIn(field, self.native)
        self.assertIn(
            "record_result runtime_integration PASS", self.native
        )
        self.assertIn("record_result vins_dataset NOT_RUN", self.native)

    def test_configured_acceptance_scripts_are_present(self) -> None:
        dataset = (ROOT / "tools/native-dataset-smoke.sh").read_text(
            encoding="utf-8"
        )
        runner = (ROOT / "tools/dataset_e2e.py").read_text(encoding="utf-8")
        hardware = (ROOT / "tools/native-hardware-smoke.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("/vins_estimator/odometry", runner)
        self.assertIn("dataset_e2e.py", dataset)
        self.assertIn("--config", dataset)
        self.assertIn("/dev/ttyAMA10:460800", hardware)
        self.assertIn("connected: true", hardware)


if __name__ == "__main__":
    unittest.main()
