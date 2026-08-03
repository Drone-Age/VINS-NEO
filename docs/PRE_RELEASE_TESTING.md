# Pre-release testing

Every planned check records one explicit result from the process-governance
state model.

## Required gates

| Gate | Acceptance condition |
|---|---|
| Metadata | Product/tag/manifest/changelog agree; signed assets and immutable commits are pinned. |
| Platform | Native Raspberry Pi 5, Debian 13, `aarch64`/`arm64`; no Docker, emulation, or cross-compilation evidence. |
| Runtime | No `iros2-0` or `/opt/iros2_0`; every required `iros2j-*` package is exactly `1.0.3-1+deb13`. |
| Build | Source `/opt/iros2j/setup.bash`; Release build and `colcon test` pass. |
| Ownership | `ros2 pkg prefix cv_bridge` is `/opt/iros2j`; `/opt/vins` has no private ROS underlay payload. |
| Package | ARM64 metadata, exact dependencies, portability, checksum, and complete ELF linkage pass. |
| Install | Clean APT install and clean-shell VINS smoke pass. |
| Integration | Source `/opt/iros2j`, `/opt/imavros`, `/opt/vins` in order; Fast DDS, topics, QoS, timestamps, and frames pass. |
| Dataset | Prepared immutable DSM run-manifest passes the VINS-owned runner on the configured Raspberry Pi 5. |
| Post-release | Published checksum, reinstall, smoke, and integration checks pass. |

The durable report MUST record test ID, result, timestamps, host, target,
exact command, commit, dependency identity, evidence path, and a reason for
every non-`PASS` result.

For configured Raspberry Pi 5 acceptance, prepare the dataset on the host over
HTTPS, set `DATASET_RUN_MANIFEST` in the ignored native environment, and run:

```powershell
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

The dataset gate requires non-empty `/imu0` and `/cam0/image_raw`, both VINS
processes alive until bag completion, and at least 10 finite, timestamp-monotonic
`/vins_estimator/odometry` messages. The result pins every dataset, profile,
artifact, configuration, suite, and Client version input. Ubuntu AMD64 evidence
is development-only; release evidence requires the native Debian 13 ARM64 run.

The separate hardware gate is `tools/native-hardware-smoke.sh
/path/to/hardware-evidence`. It captures a real OV5647 frame and requires an
ArduPilot heartbeat through `/dev/ttyAMA10` at 460800.
