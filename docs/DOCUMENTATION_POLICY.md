# Documentation policy

This policy is normative for VINS-NEO documentation and follows the common
iROS2 and iMAVROS documentation contract.

## Languages and filenames

English is canonical for automation, machine-facing interpretation,
identifiers, commands, APIs, schemas, and international integration.
Ukrainian is a mandatory maintained localization of every new or materially
changed human-facing normative document.

The canonical document uses `NAME.md`. Its Ukrainian counterpart uses
`NAME.uk.md` in the same directory. Commands, paths, identifiers, field names,
versions, package names, and tags are not translated.

`AGENTS.md` is intentionally English-only so automation receives one
unambiguous instruction source.

## Normative content

Policies, regulations, mandatory checklists, contributor rules, release
procedures, acceptance gates, and operational instructions are normative.
A normative change is complete only when:

1. both language files express equivalent requirements and acceptance
   criteria;
2. both files are updated in the same commit;
3. navigation links remain valid;
4. `PROCESS_VERSION` is incremented as required by `VERSIONING.md`;
5. the process change is recorded in `CHANGELOG.md`.

When translations disagree, English controls execution. The discrepancy is a
documentation defect and must be corrected before the next process or product
release.

## Legacy documents

The following existing Ukrainian-only documents predate this policy:

- `README_UK.md`;
- `DEVELOPMENT_STANDARDS_UK.md`;
- `LOGGING_UK.md`;
- `PRE_RELEASE_TESTING_UK.md`;
- `RELEASE_PROCESS_UK.md`;
- `config/native/README_UK.md`;
- `config/releases/README_UK.md`.

They remain valid for the current published product history. Any material
change to one of them must migrate it in the same change to a canonical
English `NAME.md` and Ukrainian `NAME.uk.md` pair. Historical instructions for
an already published tag must not be silently rewritten; superseded content
must carry a visible legacy notice.

## Requirement language

`MUST`, `MUST NOT`, `SHOULD`, and `MAY` have their usual normative meanings.
Documents must distinguish implemented behavior from a planned target and
must not advertise an unverified capability as released.
