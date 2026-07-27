# Release manifests

Every new VINS-NEO release has an immutable
`config/releases/<RELEASE_TAG>.env` file in the release commit.

Schema 2 records the VINS version/tag, exact signed `iros2j` APT snapshot and
`iros2j-*` package closure, compatible iMAVROS release/artifact identity, and
system OpenCV version. The runtime prefixes are `/opt/iros2j`, `/opt/imavros`,
and `/opt/vins`. It does not contain `CV_BRIDGE_REF`; `cv_bridge` is provided
by `iros2j-cv-bridge`.

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

Schema 1 files remain immutable historical contracts.
