#!/usr/bin/env python3
"""ROS 2 topic monitor used by the VINS-owned dataset e2e runner."""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import tempfile

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image, Imu


def stamp_ns(message) -> int:
    return int(message.header.stamp.sec) * 1_000_000_000 + int(message.header.stamp.nanosec)


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class DatasetMonitor(Node):
    def __init__(self, camera_topic: str, imu_topic: str, odometry_topic: str):
        super().__init__("vins_dataset_e2e_monitor")
        self.counts = {"camera": 0, "imu": 0, "odometry": 0}
        self.odometry_monotonic = True
        self.odometry_finite = True
        self.previous_odometry_stamp = None
        self.first_odometry_stamp = None
        self.last_odometry_stamp = None
        self.first_position = None
        self.last_position = None
        self.create_subscription(Image, camera_topic, self.camera_callback, qos_profile_sensor_data)
        self.create_subscription(Imu, imu_topic, self.imu_callback, qos_profile_sensor_data)
        self.create_subscription(
            Odometry, odometry_topic, self.odometry_callback, qos_profile_sensor_data
        )

    def camera_callback(self, _message: Image) -> None:
        self.counts["camera"] += 1

    def imu_callback(self, _message: Imu) -> None:
        self.counts["imu"] += 1

    def odometry_callback(self, message: Odometry) -> None:
        self.counts["odometry"] += 1
        stamp = stamp_ns(message)
        if self.previous_odometry_stamp is not None and stamp < self.previous_odometry_stamp:
            self.odometry_monotonic = False
        self.previous_odometry_stamp = stamp
        self.first_odometry_stamp = stamp if self.first_odometry_stamp is None else self.first_odometry_stamp
        self.last_odometry_stamp = stamp
        position = message.pose.pose.position
        orientation = message.pose.pose.orientation
        values = (
            position.x, position.y, position.z,
            orientation.x, orientation.y, orientation.z, orientation.w,
        )
        if not all(math.isfinite(value) for value in values):
            self.odometry_finite = False
        xyz = [float(position.x), float(position.y), float(position.z)]
        self.first_position = xyz if self.first_position is None else self.first_position
        self.last_position = xyz

    def result(self) -> dict:
        delta = None
        duration = None
        if self.first_position is not None and self.last_position is not None:
            dx = self.last_position[0] - self.first_position[0]
            dy = self.last_position[1] - self.first_position[1]
            dz = self.last_position[2] - self.first_position[2]
            delta = {
                "xy": math.hypot(dx, dy),
                "xyz": math.sqrt(dx * dx + dy * dy + dz * dz),
            }
        if self.first_odometry_stamp is not None and self.last_odometry_stamp is not None:
            duration = (self.last_odometry_stamp - self.first_odometry_stamp) / 1_000_000_000
        return {
            "counts": self.counts,
            "delta": delta,
            "duration_seconds": duration,
            "odometry_finite": self.odometry_finite,
            "odometry_timestamps_monotonic": self.odometry_monotonic,
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--camera-topic", required=True)
    parser.add_argument("--imu-topic", required=True)
    parser.add_argument("--odometry-topic", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    rclpy.init()
    node = DatasetMonitor(args.camera_topic, args.imu_topic, args.odometry_topic)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        atomic_json(args.output, node.result())
        node.destroy_node()
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
