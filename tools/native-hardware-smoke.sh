#!/usr/bin/env bash
set -Eeuo pipefail

evidence=${1:?usage: native-hardware-smoke.sh EVIDENCE_DIR}
mkdir -p "$evidence"

model=$(tr -d '\0' </proc/device-tree/model)
[[ $model == *"Raspberry Pi 5"* ]]
[[ $(uname -m) == aarch64 ]]
[[ -c /dev/ttyAMA10 ]]
if fuser /dev/ttyAMA10 >"$evidence/serial-users.txt" 2>/dev/null; then
  echo "/dev/ttyAMA10 is already in use" >&2
  exit 1
fi

rpicam-hello --list-cameras >"$evidence/cameras.txt" 2>&1
grep -Fq ov5647 "$evidence/cameras.txt"
rpicam-still --nopreview --timeout 1000 --output "$evidence/camera.jpg" \
  >"$evidence/camera-capture.log" 2>&1
test -s "$evidence/camera.jpg"

set +u
source /opt/iros2j/setup.bash
source /opt/imavros/setup.bash
set -u
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

cleanup() {
  for pid in "${state_pid:-}" "${mavros_pid:-}"; do
    [[ -z $pid ]] || kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

ros2 launch mavros px4.launch \
  fcu_url:=serial:///dev/ttyAMA10:460800 \
  fcu_protocol:=v2.0 tgt_system:=1 tgt_component:=1 \
  >"$evidence/mavros.log" 2>&1 &
mavros_pid=$!

for _ in {1..30}; do
  topics=$(ros2 topic list -t 2>/dev/null || true)
  if grep -Fq '/mavros/state [' <<<"$topics"; then
    break
  fi
  if ! kill -0 "$mavros_pid" 2>/dev/null; then
    echo "MAVROS exited before publishing /mavros/state" >&2
    exit 1
  fi
  sleep 1
done
grep -Fq '/mavros/state [' <<<"${topics:-}"
printf '%s\n' "$topics" >"$evidence/mavros-topics.txt"

connected=false
for _ in {1..30}; do
  if timeout 5 ros2 topic echo --once /mavros/state \
    >"$evidence/mavros-state.txt" 2>"$evidence/mavros-state.err" &&
    grep -Fq 'connected: true' "$evidence/mavros-state.txt"; then
    connected=true
    break
  fi
  sleep 1
done
$connected
test -s "$evidence/mavros-state.txt"
grep -Fq 'connected: true' "$evidence/mavros-state.txt"
grep -Fq 'system_status:' "$evidence/mavros-state.txt"

printf '%s\n' "$model" >"$evidence/platform.txt"
printf 'PASS\n' | tee "$evidence/hardware-result.txt"
