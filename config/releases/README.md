# Release manifests

Every new VINS-NEO release has an immutable
`config/releases/<RELEASE_TAG>.env` file in the release commit.

Schema 3 records the VINS version/tag, exact signed `iros2j` APT snapshot and
`iros2j-*` package closure, compatible iMAVROS release/artifact identity,
system OpenCV version, and the exact Ubuntu 24.04/Jazzy AMD64 test/deployment
asset names. The runtime prefixes are `/opt/iros2j`, `/opt/imavros`, and
`/opt/vins`. It does not contain `CV_BRIDGE_REF`; `cv_bridge` is provided by
`iros2j-cv-bridge`.

The AMD64 fields always use evidence class `development`. They make the image,
Debian package, JSON manifest, and checksum list mandatory versioned release
assets; they do not weaken or replace the Debian 13 ARM64 native release gate.

Validate the staged release:

```powershell
.\tools\check-release-metadata.ps1 `
  -Index -ReleaseTag v1_00_03_00 -VerifyAsset
```

Validate the committed release before tagging:

```powershell
.\tools\check-release-metadata.ps1 `
  -GitRef HEAD -ReleaseTag v1_00_03_00
```

Schema 1 and 2 files remain immutable historical contracts.
