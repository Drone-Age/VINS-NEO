# Versioning policy

This policy is normative for VINS-NEO versions and tags. Product and process
versions are independent.

## Product version

The VINS-NEO product version has four numeric components:

`MAJOR.MINOR.FEATURE.PATCH`

Its existing tag form remains
`vMAJOR_MINOR_FEATURE_PATCH`, with two-digit components after `MAJOR`, for
example `v1_00_02_00`. Product-version semantics and ROS package-version
mapping remain defined by `DEVELOPMENT_STANDARDS_UK.md` until that legacy
document is migrated.

A product release binds one exact final source commit, dependency manifest,
the Ubuntu 24.04 AMD64 test/deployment image and Debian package, the native
Debian 13 ARM64 production package, every artifact checksum, both gate evidence
records, the changelog entry, and release notes. AMD64 evidence is classified
as `development`; only the native ARM64 evidence can authorize a release.
Published product tags are immutable and MUST point to the commit tested by
both architecture gates.

## Process version

`PROCESS_VERSION` is a three-component semantic version for regulations,
metadata contracts, validators, release scripts, issue forms, and automation.
Process tags use `process-v<major>.<minor>.<patch>`.

- **MAJOR**: incompatible workflow, evidence contract, schema, or gate change;
- **MINOR**: backward-compatible capability or new mandatory process step;
- **PATCH**: compatible correction or clarification.

A process-only change does not change the VINS product version. A product
metadata update does not change `PROCESS_VERSION` unless it also changes the
process or tooling. When one task releases both domains, both versions and
both tags are updated after all applicable gates pass.

## Completion

A process change is complete only when the requested files and checks are
complete, `PROCESS_VERSION` is incremented, the changelog records the change,
and the corresponding immutable process tag is published from the reviewed
commit. Product releases additionally require the full native release gate.
No existing tag may be moved or reused.
