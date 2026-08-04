# Release process

This is the current release contract for VINS-NEO 1.0.3.0 and later.
Historical releases remain governed by their immutable tagged files.

## Inputs

Before the release commit, schema 3
`config/releases/<RELEASE_TAG>.env` MUST pin:

- the VINS product version and tag;
- the `iros2j` version, Debian version, source tag and commit, signed APT
  snapshot URL and SHA-256, `/opt/iros2j`, and exact `iros2j-*` closure;
- the compatible iMAVROS version, Debian version, tag, commit, artifact URL
  and SHA-256, and `/opt/imavros`;
- the system OpenCV version.
- the Ubuntu 24.04/Jazzy AMD64 test platform, `development` evidence class,
  and exact names of the versioned image, Debian package, JSON manifest, and
  checksum assets.

Before the dataset gate, a host-prepared DataSetsManager run-manifest MUST pin
the dataset ID and profile, artifact version and source/content SHA-256,
configuration SHA-256, suite version, and DataSetsManager Client version. The
dispatcher transfers those verified inputs to the Pi without the DSM token.

Schema 2 and 3 MUST NOT contain `CV_BRIDGE_REF`. VINS consumes
`iros2j-cv-bridge`; it does not clone or build `vision_opencv`.

## Gates

1. Stage the manifest, CMake version, runtime tag, changelog, scripts, tests,
   and paired documentation.
2. Run `tools/check-release-metadata.ps1 -Index -ReleaseTag <TAG>
   -VerifyAsset` and review the complete release change.
3. Merge the release change without creating a tag or GitHub Release. Record
   the exact final commit on the protected release issue and freeze it for
   both architecture gates.
4. At that exact final commit, run
   `tools/check-release-metadata.ps1 -GitRef HEAD -ReleaseTag <TAG>` and
   `tools/build-amd64-test-release.ps1 -ReleaseTag <TAG>`.
5. On Ubuntu 24.04 AMD64, run the real `iv.dev.4.ff.1` dataset e2e. Its result
   MUST be `PASS` with `development` evidence and MUST identify the same exact
   final commit. Retain the produced AMD64 test/deployment assets and hashes.
6. Prepare `iv.dev.4.ff.1` through the HTTPS DSM endpoint on the host and set
   `DATASET_RUN_MANIFEST` in the ignored native environment.
7. Run the native Debian 13 ARM64 workflow from the same exact commit with
   `tools/invoke-native-release.ps1 -InstallDependencies -InstallTest
   -IntegrationTest -DatasetTest`.
8. Audit the ARM64 Debian package, clean installation, ELF closure, exact
   `iros2j-*` dependencies, and ownership under `/opt/vins`.
9. Verify the ARM64 `dataset-e2e-result.json` is `PASS` with `release`
   evidence class and references the same exact final commit.
10. Create immutable product/process tags on that commit. The GitHub Release
    MUST include the AMD64 test/deployment image, AMD64 Debian package, AMD64
    JSON manifest, checksums and dataset evidence, plus the ARM64 production
    package, checksums, and release evidence.
11. Download every published artifact, verify its checksum, reinstall or load
    it on the matching platform, and repeat the applicable smoke and
    integration checks.

No tag or release may be created while a mandatory gate is `FAIL`, `BLOCKED`,
or `NOT_RUN`. If any fix changes the frozen commit, both AMD64 and ARM64 gates
MUST restart from the new final commit; evidence from the old commit cannot be
carried forward.
