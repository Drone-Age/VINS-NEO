# Ubuntu 24.04 AMD64 test release

Every VINS-NEO product release MUST include an Ubuntu 24.04/Jazzy AMD64 build
for the first local test cycle and deployment of reproducible test
environments. This build is versioned with the product, but it is not a
production target and cannot replace native Debian 13 ARM64 release evidence.

## Build contract

Run from a clean checkout of the exact final release commit:

```powershell
pwsh ./tools/build-amd64-test-release.ps1 `
  -ReleaseTag v1_00_03_00 `
  -OutputDirectory ./output/amd64-release
```

The command MUST fail for a dirty worktree, metadata mismatch, non-AMD64
image, failed `colcon test`, failed repository contract, incorrect image
revision label, invalid Debian package identity, failed clean package-install
smoke, or asset write failure.

The same builder is exposed by the manual **Ubuntu 24 AMD64 test release**
GitHub Actions workflow. Dispatch it on the frozen final commit, not on a
moving branch. Its retained workflow artifact is an intermediate handoff;
the files still MUST be attached to the versioned GitHub Release after the
ARM64 gate passes.

The output contract is pinned by schema 3 of
`config/releases/<RELEASE_TAG>.env` and contains:

- a Docker image archive with the installed VINS overlay, RViz dependencies,
  and the VINS-owned dataset runner;
- an Ubuntu 24.04/Jazzy AMD64 Debian package;
- a JSON build manifest that records `PASS`, `development`, product/tag,
  exact source commit, platform, image ID, package identity, sizes, and hashes;
- one `SHA256SUMS` file for the three preceding assets.

The image is produced only from the Docker `test` stage, so failed unit or
contract tests prevent the image and package from being emitted. The image
supports `shell`, `version`, and tokenless `dataset-e2e --run-manifest ...`
entrypoints. Prepared manifest artifact/config paths MUST be mounted at the
same absolute paths inside the container.

The Debian asset is installed in a separate VINS-free Ubuntu/Jazzy dependency
stage and MUST run `vins_estimator --version` before the final package can be
exported.

## Release acceptance

On the same exact commit, run the real `iv.dev.4.ff.1` smoke suite on Ubuntu
24.04 AMD64 and retain `dataset-e2e-result.json` as `development` evidence.
Then repeat the dataset and native package/integration gates on Debian 13
ARM64; only that result is `release` evidence.

After both gates pass, attach all AMD64 assets and the AMD64
`dataset-e2e-result.json` alongside the ARM64 production assets/evidence to the
versioned GitHub Release. If a fix changes the source commit, discard both
architecture evidence sets and rebuild/retest from the new exact final commit.
