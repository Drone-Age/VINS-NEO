# Process governance

This policy aligns VINS-NEO task, release, and evidence handling with iROS2
and iMAVROS while preserving VINS-specific product gates.

## Work tracking

Material implementation, process, documentation, packaging, and release work
must have one open GitHub Issue and one ClickUp task with reciprocal links and
approved scope before implementation begins.

GitHub is authoritative for source, commits, pull requests, tags, releases,
technical scope, acceptance criteria, logs, checksums, manifests, and
immutable evidence. ClickUp is authoritative for planning status, owner,
priority, schedule, business scope, blockers, and cross-component
coordination.

Both items must identify the objective, scope and exclusions, applicable
product/process version, ordered stages, acceptance criteria, risks,
dependencies, blockers, and evidence links. A stage is complete only after its
stated check has produced durable evidence.

## Checkpoints and continuity

Record a checkpoint after scope or version changes, reviewed commits, gate
results, blocker changes, manifest finalization, publication, and post-release
verification. Each checkpoint records the exact commit, completed and next
stage, executed checks with explicit result, evidence links, and any required
owner action.

Before resuming work, compare Git state, the GitHub Issue, and the ClickUp task
to locate the last verified checkpoint. Do not repeat a passed gate when its
inputs and evidence remain unchanged. Do not create duplicate tasks when
linkage is uncertain.

## Estimates and time

Before active work, the ClickUp task must contain a tracked-work estimate,
confidence, risks, expected machine time, and expected external wait. Use the
ClickUp timer for active analysis, implementation, review, monitored builds,
verification, documentation, and publication. Stop it during unsupervised
execution or while waiting for user input, credentials, hardware, or external
approval.

Re-estimate after initial audit, first representative build, material scope or
blocker changes, and before a release gate. Preserve the initial estimate and
record the reason and evidence for every revision.

## Test and evidence states

Every planned check has exactly one result:

- `PASS`: completed and all acceptance conditions passed;
- `FAIL`: completed with at least one failed condition;
- `BLOCKED`: applicable but unable to complete because a required input or
  environment is unavailable;
- `SKIPPED_NOT_CONFIGURED`: requires hardware absent from the approved target
  configuration;
- `SKIPPED_NOT_APPLICABLE`: outside the selected scope or product;
- `NOT_RUN`: not attempted and no approved skip applies.

Never report partial, timed-out, skipped, or blocked work as `PASS`. Evidence
must include test ID, result, timestamps, host, target, exact command, source
commit, dependency/manifest identity, artifact checksums where applicable,
evidence location, and reason for every non-`PASS` result.

A mandatory `FAIL` fails the gate. A mandatory `BLOCKED`, `NOT_RUN`, or
unaccepted skip blocks the gate. Plain `PASS` is allowed only when every
applicable mandatory check passed.

## Release contract

The release commit must pin the exact iROS2 input used by VINS-NEO and, when
iMAVROS is part of the selected integration scope, the exact iMAVROS input.
Each pinned input includes its released version, immutable asset URL, package
metadata, and SHA-256. Dependency selection occurs before the release commit
and must not be deferred to build time.

Official VINS-NEO ARM64 artifacts are built and tested natively on the
approved Debian 13 Raspberry Pi 5 target. Docker, emulation, cross-compilation,
and another architecture may support diagnostics but are not native release
evidence.

Create a product tag only after metadata, native build, automated tests,
package audit, clean install, runtime smoke test, and VINS dataset gate pass.
After publication, download the published artifact, verify its checksum,
install it through the supported package path, and repeat the required smoke
test. Tags and published version identities are immutable.

## Completion and blockers

Do not close the GitHub Issue or set ClickUp to a terminal state until all
acceptance criteria and mandatory gates pass, final commits and tags are
published, evidence links are present, versions and documentation match the
published state, and the terminal write is read back and verified.

When blocked, record the exact missing input, the last successful checkpoint,
remaining mandatory items, and the safe resume action. A blocker does not
become completion and does not authorize weakening a gate.
