"""Launch and local-development contracts that do not require a ROS graph."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LaunchContractTest(unittest.TestCase):
    def test_combined_launch_exposes_public_arguments_and_two_nodes(self):
        launch = (ROOT / "vins_estimator/launch/vins_neo.launch.py").read_text(
            encoding="utf-8"
        )
        for argument in (
            "config_file",
            "vins_folder",
            "use_sim_time",
            "log_level",
            "logging_period_ms",
        ):
            self.assertRegex(launch, rf"DeclareLaunchArgument\(\s*'{argument}'")
        self.assertIn("package='feature_tracker'", launch)
        self.assertIn("package='vins_estimator'", launch)
        self.assertIn("common_parameters", launch)

    def test_separate_launches_accept_config_and_keep_euroc_default(self):
        paths = (
            ROOT / "feature_tracker/launch/vins_feature_tracker.launch.py",
            ROOT / "feature_tracker/launch/vins_feature_tracker_rviz.launch.py",
            ROOT / "vins_estimator/launch/euroc.launch.py",
        )
        for path in paths:
            with self.subTest(path=path.name):
                launch = path.read_text(encoding="utf-8")
                self.assertIn("DeclareLaunchArgument", launch)
                self.assertIn("'config_file'", launch)
                self.assertIn("config/euroc/euroc_config.yaml", launch)
                self.assertIn("'config_file': config_file", launch)

    def test_compose_uses_ubuntu_jazzy_amd64_development_stage(self):
        compose = (ROOT / "compose.yaml").read_text(encoding="utf-8")
        dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
        self.assertIn("target: development", compose)
        self.assertIn("platform: linux/amd64", compose)
        self.assertIn("ROS_DISTRO: jazzy", compose)
        self.assertIn("FROM development AS build", dockerfile)

    def test_existing_nine_tests_are_individually_registered_in_colcon(self):
        cmake = (ROOT / "vins_estimator/CMakeLists.txt").read_text(encoding="utf-8")
        existing = (ROOT / "tests/test_iros2j_migration.py").read_text(encoding="utf-8")
        methods = [
            line.split("def ", 1)[1].split("(", 1)[0]
            for line in existing.splitlines()
            if line.startswith("    def test_")
        ]
        self.assertEqual(9, len(methods))
        for method in methods:
            self.assertIn(method, cmake)


if __name__ == "__main__":
    unittest.main()
