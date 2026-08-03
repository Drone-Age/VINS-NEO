#!/usr/bin/env bash
set -Eeuo pipefail

bag=${1:?usage: native-dataset-smoke.sh BAG CONFIG EVIDENCE_DIR}
config=${2:?usage: native-dataset-smoke.sh BAG CONFIG EVIDENCE_DIR}
evidence=${3:?usage: native-dataset-smoke.sh BAG CONFIG EVIDENCE_DIR}

printf '%s\n' \
  'WARNING: native-dataset-smoke.sh is a deprecated expert override.' \
  'Use dataset_e2e.py with a DataSetsManager run-manifest.' >&2

set +u
source /opt/iros2j/setup.bash
source /opt/imavros/setup.bash
source /opt/vins/setup.bash
set -u
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

exec python3 "$(dirname "$0")/dataset_e2e.py" \
  --dataset-id deprecated.expert.override \
  --suite smoke \
  --bag "$bag" \
  --config "$config" \
  --evidence-dir "$evidence"
