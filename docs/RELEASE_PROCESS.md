# Release process

This is the current release contract for VINS-NEO 1.0.3.0 and later.
Historical releases remain governed by their immutable tagged files.

## Inputs

Before the release commit, `config/releases/<RELEASE_TAG>.env` MUST pin:

- the VINS product version and tag;
- the `iros2j` version, Debian version, source tag and commit, signed APT
  snapshot URL and SHA-256, `/opt/iros2j`, and exact `iros2j-*` closure;
- the compatible iMAVROS version, Debian version, tag, commit, artifact URL
  and SHA-256, and `/opt/imavros`;
- the system OpenCV version.

Before the dataset gate, a host-prepared DataSetsManager run-manifest MUST pin
the dataset ID and profile, artifact version and source/content SHA-256,
configuration SHA-256, suite version, and DataSetsManager Client version. The
dispatcher transfers those verified inputs to the Pi without the DSM token.

Schema 2 MUST NOT contain `CV_BRIDGE_REF`. VINS consumes
`iros2j-cv-bridge`; it does not clone or build `vision_opencv`.

## Gates

1. Stage the manifest, CMake version, runtime tag, changelog, scripts, tests,
   and paired documentation.
2. Run `tools/check-release-metadata.ps1 -Index -ReleaseTag <TAG>
   -VerifyAsset`.
3. Review and commit the complete release change.
4. Run `tools/check-release-metadata.ps1 -GitRef HEAD -ReleaseTag <TAG>`.
5. Prepare `iv.dev.4.ff.1` through the HTTPS DSM endpoint on the host and set
   `DATASET_RUN_MANIFEST` in the ignored native environment.
6. Run the native Debian 13 ARM64 workflow with
   `tools/invoke-native-release.ps1 -InstallDependencies -InstallTest
   -IntegrationTest -DatasetTest`.
7. Audit the Debian package, clean installation, ELF closure, exact
   `iros2j-*` dependencies, and ownership under `/opt/vins`.
8. Verify `dataset-e2e-result.json` is `PASS` with `release` evidence class.
9. Merge the reviewed commit, then create immutable product/process tags and
   release assets.
10. Download the published artifact, verify its checksum, reinstall it, and
   repeat the smoke and integration checks.

No tag or release may be created while a mandatory gate is `FAIL`, `BLOCKED`,
or `NOT_RUN`.
