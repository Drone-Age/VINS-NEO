# Native release environment

Official release evidence is produced only on the configured Raspberry Pi 5
running Debian 13 ARM64. Copy `native.env.example` to the ignored
`native.env`, then set the approved host and output directory. Prepare the DSM
run-manifest on the host through HTTPS and set `DATASET_RUN_MANIFEST`. The
dispatcher packages the verified artifact, VINS configuration, and relative
run-manifest for the Pi; `DSM_SERVER_TOKEN` is not transferred.

The dispatcher verifies the exact target identity, transfers an archive of
the selected Git revision into an isolated directory, and runs the tracked
native script:

```powershell
.\tools\invoke-native-release.ps1 -PreflightOnly
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

The runtime is activated in the order `/opt/iros2j`, `/opt/imavros`,
`/opt/vins`. `VINS_CONFIG` and `DATASET` are deprecated expert overrides for
one compatibility cycle. `native.env`, DSM keys, and SSH credentials MUST NOT
be committed.
