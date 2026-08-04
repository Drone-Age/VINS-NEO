import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def parse_manifest() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in read("config/releases/v1_00_03_00.env").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    return values


class Amd64ReleaseContractTest(unittest.TestCase):
    def test_schema_three_pins_test_platform_and_assets(self) -> None:
        manifest = parse_manifest()
        self.assertEqual(manifest["MANIFEST_SCHEMA"], "3")
        self.assertEqual(manifest["AMD64_TEST_OS"], "ubuntu-24.04")
        self.assertEqual(manifest["AMD64_TEST_ARCH"], "amd64")
        self.assertEqual(manifest["AMD64_TEST_ROS_DISTRO"], "jazzy")
        self.assertEqual(
            manifest["AMD64_TEST_EVIDENCE_CLASS"], "development"
        )
        version = manifest["PRODUCT_VERSION"]
        self.assertEqual(
            manifest["AMD64_TEST_IMAGE_ASSET"],
            f"vins-neo_{version}_ubuntu24-amd64-test-env.tar",
        )
        self.assertEqual(
            manifest["AMD64_TEST_DEB_ASSET"],
            f"vins-mono-ros2_{version}_amd64.deb",
        )

    def test_image_is_built_only_after_colcon_tests_pass(self) -> None:
        dockerfile = read("Dockerfile")
        self.assertIn("FROM build AS test", dockerfile)
        self.assertIn("--return-code-on-test-failure", dockerfile)
        self.assertIn("FROM dependencies AS test-runtime", dockerfile)
        self.assertIn("COPY --from=test ${VINS_WS}/install/", dockerfile)
        self.assertIn(
            'org.drone-age.vins.evidence-class="development"', dockerfile
        )

    def test_builder_requires_clean_exact_commit_and_amd64(self) -> None:
        builder = read("tools/build-amd64-test-release.ps1")
        self.assertIn("git status --porcelain=v1", builder)
        self.assertIn("git rev-parse --verify 'HEAD^{commit}'", builder)
        self.assertIn('"--platform", "linux/amd64"', builder)
        self.assertIn("Built image revision label", builder)
        self.assertIn("Get-FileHash -Algorithm SHA256", builder)

    def test_runtime_supports_version_and_dataset_e2e(self) -> None:
        entrypoint = read("docker/test-runtime-entrypoint.sh")
        self.assertIn('source "${VINS_PREFIX:-/opt/vins}/setup.bash"', entrypoint)
        self.assertIn("dataset-e2e)", entrypoint)
        self.assertIn("dataset_e2e.py", entrypoint)
        self.assertIn("vins_estimator --version", entrypoint)

    def test_release_docs_keep_architecture_roles_separate(self) -> None:
        release = read("docs/RELEASE_PROCESS.md")
        testing = read("docs/PRE_RELEASE_TESTING.md")
        self.assertIn("exact final commit", release)
        self.assertIn("AMD64 test/deployment", release)
        self.assertIn("native Debian 13 ARM64", release)
        self.assertIn("does not authorize", testing)
        self.assertIn("development", testing)
        self.assertIn("release", testing)

    def test_normative_amd64_document_has_ukrainian_pair(self) -> None:
        for path in (
            "docs/AMD64_TEST_RELEASE.md",
            "docs/AMD64_TEST_RELEASE.uk.md",
        ):
            text = read(path)
            self.assertIn("Ubuntu 24.04", text)
            self.assertIn("AMD64", text)
            self.assertIn("ARM64", text)

    def test_release_issue_template_requires_both_gates(self) -> None:
        template = read(".github/ISSUE_TEMPLATE/release.yml")
        self.assertIn("Ubuntu 24.04 AMD64 test/deployment gate", template)
        self.assertIn("Native Debian 13 ARM64 release gate", template)
        self.assertIn("AMD64 test/deployment assets", template)


if __name__ == "__main__":
    unittest.main()
