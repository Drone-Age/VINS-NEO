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
| Dataset | Controlled VINS dataset passes on the configured Raspberry Pi 5. |
| Post-release | Published checksum, reinstall, smoke, and integration checks pass. |

The durable report MUST record test ID, result, timestamps, host, target,
exact command, commit, dependency identity, evidence path, and a reason for
every non-`PASS` result.

For configured Raspberry Pi 5 acceptance, run:

```bash
tools/native-dataset-smoke.sh /path/to/ros2_bag /path/to/dataset-evidence
tools/native-hardware-smoke.sh /path/to/hardware-evidence
```

The dataset gate requires `/imu0`, `/cam0/image_raw`, and a produced
`/vins_estimator/odometry` message. The hardware gate captures a real OV5647
frame and requires an ArduPilot heartbeat through `/dev/ttyAMA10` at 460800.
