# Native release environment

Official release evidence is produced only on the configured Raspberry Pi 5
running Debian 13 ARM64. Copy `native.env.example` to the ignored
`native.env`, then set the approved host, output directory, VINS
configuration, dataset, and dataset runner.

The dispatcher verifies the exact target identity, transfers an archive of
the selected Git revision into an isolated directory, and runs the tracked
native script:

```powershell
.\tools\invoke-native-release.ps1 -PreflightOnly
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

The runtime is activated in the order `/opt/iros2j`, `/opt/imavros`,
`/opt/vins`. `native.env` and SSH credentials MUST NOT be committed.
