# Release history

All notable changes to VINS-MONO-ROS2 are documented in this file.

The product version uses four numeric components: `MAJOR.MINOR.FEATURE.PATCH`.
Git tags use the corresponding `vMAJOR_MINOR_FEATURE_PATCH` format, with
two-digit zero-padded components after the major version.

## [v1_00_03_00] - Unreleased

### Changed

- Migrated the release contract to the signed split-package `iros2j` 1.0.3
  snapshot under `/opt/iros2j`, compatible with iMAVROS 1.0.0.2.
- Declared the exact `iros2j-*` package closure required by VINS instead of
  depending on the obsolete monolithic `iros2-0` package.

### Removed

- Removed the release-manifest contract for a private `cv_bridge` overlay;
  `cv_bridge` is supplied by `iros2j-cv-bridge`.

## Process [1.1.0] - Unreleased

### Changed

- Added the schema 2 signed `iros2j` APT snapshot and iMAVROS compatibility
  contract to release metadata, native dispatch, package ownership audits,
  integration activation, and paired normative documentation.
- Retained schema 1 validation only for immutable historical releases.
- Added reproducible ROS 2 dataset/odometry and configured Pi camera/FCU
  hardware acceptance gates.

## Process [1.0.0] - 2026-07-28

### Added

- Added independent process versioning for regulations and release tooling.
- Aligned task tracking, evidence states, native release gates, immutable tags,
  and post-release verification with the iROS2 and iMAVROS process contract.
- Established canonical English and mandatory Ukrainian normative
  documentation, with an explicit migration rule for legacy `*_UK.md` files.

## [v1_00_02_00] - 2026-07-26

### Changed

- Updated the native Debian 13 ARM64 release to the stable IROS2_0
  `0.1.2-1+deb13` package.
- Kept the exact Debian dependency on the release-pinned IROS2_0 package.

### Removed

- Removed the obsolete ARM64 Docker build, release, runtime, and emulation
  workflows. Official ARM64 packages are built and tested only on the native
  Debian 13 target.

## [v1_00_01_07] - 2026-07-24

### Added

- Added reproducible Debian 13 ARM64 release and runtime Docker workflows based
  on the published IROS2_0 `0.1.1-1+deb13` package.
- Added a ready-package runtime test stack for launching the feature tracker,
  estimator, RViz, and ROS 2 bag playback without recompiling VINS.
- Added the pinned `cv_bridge` 4.1.0 overlay because it is not included in the
  IROS2_0 runtime package.
- The successful initialization report now includes compact motion-dependent
  diagnostics: metric scale, IMU excitation, visual parallax, gravity before
  world-frame alignment, and the initial alignment orientation.
- Added time-offset estimation mode, extrinsic parameter source, and aggregate
  triangulated-feature depth statistics without dumping individual landmarks
  or feature tracks.
- Added RViz2 to the Docker runtime and a standalone VINS RViz launch file.

### Fixed

- Initialized the IMU excitation accumulator to zero before summing
  preintegrated accelerations.
- Migrated the custom pose, quaternion, and yaw parameterizations from the
  removed Ceres `LocalParameterization` API to the Ceres 2 `Manifold` API.
- Replaced non-standard variable-length arrays and deprecated ROS message
  pointer aliases for C++17 and ROS 2 Jazzy compatibility.

### Changed

- All project packages now compile as C++17.
- OpenCV color conversion constants use the OpenCV 4 API.

### Documentation

- Documented the verified Windows 11 ARM64 Docker build and smoke-test for
  ROS 2 Jazzy, OpenCV 4.6, Ceres 2.2, and Eigen 3.4.

## [v0_00_01_05] - 2026-07-23

### Changed

- Removed sensor timestamps from periodic status, state transitions, waiting
  output, and the successful initialization report. The ROS log prefix remains
  the single displayed time source.
- Shortened periodic INFO field names and numeric precision so initialization
  and tracking telemetry fit on one terminal line.

### Documentation

- Added Ukrainian user and logging guides covering build, configuration,
  startup, runtime states, initialization output, diagnostics, version
  reporting, log levels, color output, and INFO throttling.

## [v0_00_01_04] - 2026-07-23

### Fixed

- Waiting output is emitted immediately and periodically reports whether IMU
  and camera feature data are missing or being received.
- Periodic initialization and tracking telemetry is sent through the ROS INFO
  logger so it is displayed immediately by `ros2 launch`.
- Current tracking position, orientation, velocity, feature count, time offset,
  and processing time are visible at every configured reporting interval.
- Successful initialization is printed as a complete multi-line block,
  including pose, velocity, biases, gravity, timing, camera count, extrinsic
  mode, and per-camera extrinsic parameters.

## [v0_00_01_03] - 2026-07-23

### Added

- Periodically updated waiting status with current time, message counters, and
  the latest IMU and feature timestamps.
- Forced terminal color support for warning and error severity output.

### Changed

- Estimator launch now uses an emulated TTY so live status updates and colors
  are rendered immediately.
- Ceres progress output is suppressed at the INFO level, including during
  initial SFM.
- Low-level initialization and marginalization details are available only at
  the DEBUG level.

## [v0_00_01_02] - 2026-07-23

### Changed

- Periodic initialization and tracking telemetry now updates a single terminal
  status line instead of appending one line per reporting interval.
- Initialization diagnostics are consolidated into the live status line.

## [v0_00_01_01] - 2026-07-23

### Added

- Estimator version banner at process startup.
- `--version` and `-V` command-line options for querying the installed
  estimator version.

### Changed

- All ROS package manifests now report the ROS-compatible version `0.0.1`.
- Product versioning now uses the four-component `0.0.1.1` format.

## [v0_00_01_00] - 2026-07-23

### Added

- Configurable estimator logging levels and throttling period.
- Timestamped runtime telemetry for initialization and tracking states.
- Explicit state-transition and initialization-summary messages.
- Dedicated feature-tracker launch file with RViz visualization.

### Changed

- Ceres iteration logging is now enabled only at the `DEBUG` level.
- Feature tracking and RViz can now be launched separately.
- Critical estimator conditions are reported at the `ERROR` level.

## [v0_00_00_00] - 2026-07-23

Initial release of the VINS-MONO ROS 2 port.

### Added

- ROS 2 packages for camera models, feature tracking, state estimation,
  pose-graph optimization, benchmarking, the AR demo, and shared configuration.
- Launch files and configurations for EuRoC and other supported datasets.
- RViz configurations and sample benchmark data.
- Initial project documentation and GPLv3 licensing information.

[v1_00_02_00]: https://github.com/Drone-Age/VINS-NEO/releases/tag/v1_00_02_00
[v1_00_01_07]: https://github.com/NeoUKR/VINS-NEO/releases/tag/v1_00_01_07
[v0_00_01_05]: https://github.com/NeoUKR/VINS-MONO-ROS2/releases/tag/v0_00_01_05
[v0_00_01_04]: https://github.com/NeoUKR/VINS-MONO-ROS2/releases/tag/v0_00_01_04
[v0_00_01_03]: https://github.com/NeoUKR/VINS-MONO-ROS2/releases/tag/v0_00_01_03
[v0_00_01_02]: https://github.com/NeoUKR/VINS-MONO-ROS2/releases/tag/v0_00_01_02
[v0_00_01_01]: https://github.com/NeoUKR/VINS-MONO-ROS2/releases/tag/v0_00_01_01
[v0_00_01_00]: https://github.com/NeoUKR/VINS-MONO-ROS2/releases/tag/v0_00_01_00
[v0_00_00_00]: https://github.com/NeoUKR/VINS-MONO-ROS2/releases/tag/v0_00_00_00
