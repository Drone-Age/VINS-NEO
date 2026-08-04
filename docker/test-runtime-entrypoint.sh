#!/usr/bin/env bash
set -e

source "/opt/ros/${ROS_DISTRO:-jazzy}/setup.bash"
source "${VINS_PREFIX:-/opt/vins}/setup.bash"

case "${1:-shell}" in
  shell)
    shift
    exec bash "$@"
    ;;
  dataset-e2e)
    shift
    exec python3 "${VINS_TOOLS:-/opt/vins-neo/tools}/dataset_e2e.py" "$@"
    ;;
  version)
    shift
    exec ros2 run vins_estimator vins_estimator --version "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
