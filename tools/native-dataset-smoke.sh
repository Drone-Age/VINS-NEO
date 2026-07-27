#!/usr/bin/env bash
set -Eeuo pipefail

bag=${1:?usage: native-dataset-smoke.sh BAG EVIDENCE_DIR}
evidence=${2:?usage: native-dataset-smoke.sh BAG EVIDENCE_DIR}
mkdir -p "$evidence"

set +u
source /opt/iros2j/setup.bash
source /opt/imavros/setup.bash
source /opt/vins/setup.bash
set -u
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

cleanup() {
  for pid in "${echo_pid:-}" "${bag_pid:-}" "${estimator_pid:-}" \
    "${tracker_pid:-}"; do
    [[ -z $pid ]] || kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

ros2 bag info "$bag" | tee "$evidence/bag-info.txt"
grep -Fq 'Topic: /imu0 | Type: sensor_msgs/msg/Imu' \
  "$evidence/bag-info.txt"
grep -Fq 'Topic: /cam0/image_raw | Type: sensor_msgs/msg/Image' \
  "$evidence/bag-info.txt"

rm -rf /tmp/vins_output
mkdir -p /tmp/vins_output

ros2 launch feature_tracker vins_feature_tracker.launch.py \
  >"$evidence/feature-tracker.log" 2>&1 &
tracker_pid=$!
ros2 launch vins_estimator euroc.launch.py \
  >"$evidence/vins-estimator.log" 2>&1 &
estimator_pid=$!

for _ in {1..30}; do
  nodes=$(ros2 node list 2>/dev/null || true)
  if grep -Fq '/feature_tracker/feature_tracker' <<<"$nodes" &&
    grep -Fq '/vins_estimator/vins_estimator' <<<"$nodes"; then
    break
  fi
  sleep 1
done
grep -Fq '/feature_tracker/feature_tracker' <<<"${nodes:-}"
grep -Fq '/vins_estimator/vins_estimator' <<<"${nodes:-}"
printf '%s\n' "$nodes" >"$evidence/nodes.txt"

timeout 240 ros2 topic echo --once /vins_estimator/odometry \
  >"$evidence/odometry.txt" 2>"$evidence/odometry.err" &
echo_pid=$!
ros2 bag play "$bag" --rate 2.0 \
  >"$evidence/bag-play.log" 2>&1 &
bag_pid=$!

wait "$bag_pid"
bag_pid=
wait "$echo_pid"
echo_pid=

test -s "$evidence/odometry.txt"
grep -Eq 'stamp:|frame_id:' "$evidence/odometry.txt"
if grep -Eiq 'segmentation fault|terminate called|failed to load' \
  "$evidence/feature-tracker.log" "$evidence/vins-estimator.log"; then
  echo "Fatal VINS log signature detected" >&2
  exit 1
fi
printf 'PASS\n' | tee "$evidence/dataset-result.txt"
