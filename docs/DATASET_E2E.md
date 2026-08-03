# DataSetsManager dataset e2e

VINS-NEO owns the ROS 2 launch, runtime checks, cleanup, and result evidence.
DataSetsManager Client owns dataset/profile resolution, immutable artifacts,
checksums, and the validated VINS configuration.

The first supported contract is dataset `iv.dev.4.ff.1`, runtime profile
`dev_04`, implementation `vins-neo`, and suite `smoke`. The profile comes from
the dataset manifest. A manually supplied profile is only an assertion.

## Ubuntu 24.04 AMD64 development run

Install DataSetsManager Client 1.1.0 or use its development checkout. Set the
dedicated `user` key only in the process environment, never in a command line,
file, log, or evidence directory:

```bash
export DSM_SERVER_TOKEN='<dedicated e2e user key>'
dsm-client prepare-run iv.dev.4.ff.1 \
  --implementation vins-neo --suite smoke --format rosbag2 \
  --server-url https://datasetsmanager.drone-age.org \
  > /tmp/iv.dev.4.ff.1-run-manifest.json

python3 tools/dataset_e2e.py \
  --dataset-id iv.dev.4.ff.1 --suite smoke \
  --dsm-server-url https://datasetsmanager.drone-age.org \
  --evidence-dir evidence/iv.dev.4.ff.1-amd64
```

The runner may invoke `dsm-client prepare-run` directly, as in the second
command. A prepared manifest is also accepted with `--run-manifest`; that mode
does not require a DSM token.

The local development sequence is:

```bash
docker compose build
docker compose run --rm vins build
docker compose run --rm vins test
# Run DataSetsManager Client contract and fixture-integration tests in its repo.
# Then run tools/dataset_e2e.py against the real immutable dataset.
```

The combined launch is `vins_estimator vins_neo.launch.py`. It passes one
`config_file` to both nodes and exposes `vins_folder`, `use_sim_time`,
`log_level`, and `logging_period_ms`. Existing separate launches keep the
EuRoC configuration as their default.

## Acceptance and evidence

`dataset-e2e-result.json` is `PASS` only when:

- `ros2 bag info` accepts a non-fixture artifact;
- camera and IMU bag topics exist, have the expected types, and are active at
  runtime;
- feature tracker and estimator stay alive through playback;
- at least 10 odometry messages are observed;
- odometry timestamps are monotonic and position/orientation values are finite.

The result pins dataset ID, profile, artifact version/source/content SHA-256,
configuration SHA-256, suite version, and DSM Client version. Counts, duration,
Delta XY/XYZ, CPU time, and peak RSS are baseline measurements; Delta does not
block while no ground truth is available. Authentication, checksum/profile
mismatch, missing topics, early exit, timeout, and missing odometry are explicit
`FAIL` results. Cleanup runs for PASS, FAIL, timeout, and interruption.

Ubuntu 24.04 AMD64 produces `development` evidence. Only a repeat on native
Debian 13 ARM64 outside Docker can produce `release` evidence.

## Tokenless Raspberry Pi handoff

Prepare the run manifest and download/verify the artifact on the host through
HTTPS. Set `DATASET_RUN_MANIFEST` in ignored `config/native/native.env`, then
run:

```powershell
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

The dispatcher copies the verified artifact, configuration, and a rewritten
relative-path manifest to the Pi. The native workflow activates `iros2j` from
`/opt/iros2j` before the VINS overlay. It never transfers `DSM_SERVER_TOKEN`.
`--dataset` and `--vins-config` remain deprecated expert overrides for one
compatibility cycle.
