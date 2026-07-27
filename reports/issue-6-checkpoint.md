# Issue #6 implementation checkpoint

Recorded: `2026-07-28T01:51:37+03:00`

Source base: `5d73c08` (`process-v1.0.0`)

Working branch: `agent/issue-6-iros2j-runtime`

## Local results

| test_id | result | host | target | command | evidence | reason | requirement_effect |
|---|---|---|---|---|---|---|---|
| migration_regression | PASS | local Windows host | source and metadata | `python -m unittest discover -s tests -v` | 8 tests passed | | satisfied |
| native_script_syntax | PASS | local WSL Bash | native dispatcher payload | `bash -n tools/native-release.sh` | exit 0 | | satisfied |
| powershell_syntax | PASS | local Windows host | metadata validator and dispatcher | `[scriptblock]::Create(...)` | both scripts parsed | | satisfied |
| metadata_static | PASS | local Windows host | staged schema 2 release contract | `tools/check-release-metadata.ps1 -Index -ReleaseTag v1_00_03_00` with isolated index | product `1.0.3.0`, iros2j Debian `1.0.3-1+deb13` | | satisfied |
| iros2j_asset | PASS | local Windows host | published signed APT snapshot | `tools/check-release-metadata.ps1 -Index -ReleaseTag v1_00_03_00 -VerifyAsset` | downloaded SHA-256 matched `b5f01c8594ff60007819dc246a391dd4b10f1b91a92ebd8a1799d594dac25316` | | satisfied |
| imavros_asset | BLOCKED | github.com | iMAVROS 1.0.0.2 release artifact | `curl.exe -I -L https://github.com/Drone-Age/iMAVROS-release/releases/download/v1.0.0.2/imavros_1.0.0.2-1+deb13_arm64.deb` | HTTP 404 | release page and required immutable asset are not published | blocked |
| native_access | BLOCKED | `rpi@192.168.144.106` | configured Raspberry Pi 5 | `ssh -o BatchMode=yes -o ConnectTimeout=10 rpi@192.168.144.106 ...` | `Permission denied (publickey,password)` | approved credentials are unavailable to this workspace session | blocked |

## Remaining mandatory gates

- Verify the published iMAVROS 1.0.0.2 artifact and SHA-256.
- Run native build, `colcon test`, package, ELF, ownership, and clean-install
  gates on the configured Raspberry Pi 5.
- Run iros2j → iMAVROS → VINS Fast DDS, QoS, topic, timestamp, and frame
  integration gates.
- Run the controlled VINS dataset and configured-camera/FCU gates.
- Review, merge, tag, publish, download, reinstall, and post-release verify.

## Resume conditions

1. Publish the immutable iMAVROS 1.0.0.2 GitHub Release with
   `imavros_1.0.0.2-1+deb13_arm64.deb` matching the pinned SHA-256.
2. Make an approved non-interactive SSH credential for
   `rpi@192.168.144.106` available without copying private keys into the
   repository.

## Resumed native acceptance

Both resume conditions were satisfied later on 2026-07-28. The authenticated
private iMAVROS release asset matched SHA-256
`5a6f7833cc8c1ec97e6d13d2877ec061067034e5cfe466cee7859a2ceeb0b065`.
The configured target accepted its dedicated local SSH identity.

| test_id | result | host | evidence |
|---|---|---|---|
| tagged_native_release | PASS | `rpi@192.168.144.106` | `/home/rpi/vins-neo-release/v1_00_03_00/20260728-023224-eadb6fac3f15/evidence` |
| ros2_dataset_odometry | PASS | `rpi@192.168.144.106` | `/home/rpi/vins-neo-release/v1_00_03_00/dataset-evidence` |
| configured_camera_fcu | PASS | `rpi@192.168.144.106` | `/home/rpi/vins-neo-release/v1_00_03_00/hardware-evidence` |

The dataset gate converted the immutable ROS 1 input into an isolated ROS 2
Jazzy sqlite bag, preserved 34,776 `/imu0` and 8,725 `/cam0/image_raw`
messages, and observed `/vins_estimator/odometry`. The hardware gate captured
an OV5647 frame and received an ArduPilot heartbeat as MAVLink system/component
`1.1` through `/dev/ttyAMA10` at 460800.
