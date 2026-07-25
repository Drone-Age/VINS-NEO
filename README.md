# VINS-MONO-ROS2
## ROS2 version of VINS-MONO
**Current version: [v1_00_01_07](CHANGELOG.md#v1_00_01_07---2026-07-24)**

The Debian 13 ARM64 release uses the ready-made
[IROS2_0 v0.1.1](https://github.com/Drone-Age/iros2_0/releases/tag/v0.1.1)
ROS 2 Jazzy underlay. Docker verifies the package SHA-256 and builds only the
VINS overlay; the resulting `vins-mono-ros2` package depends on the exact
`iros2-0` Debian package version. Because IROS2_0 does not ship `cv_bridge`,
the release overlay builds `cv_bridge` 4.1.0 from its pinned upstream Git SHA.

## Документація українською

- [Посібник користувача: встановлення, конфігурація, запуск і діагностика](docs/README_UK.md)
- [Docker: розгортання, ARM64/Raspberry Pi, shell і тестування](docs/DOCKER_UK.md)
- [Журналювання, рівні, період INFO та формати станів](docs/LOGGING_UK.md)
- [Історія змін](CHANGELOG.md)
- [Стандарти розробки та версіонування](docs/DEVELOPMENT_STANDARDS_UK.md)
- [Стандарт передрелізного тестування](docs/PRE_RELEASE_TESTING_UK.md)
- [Стандарт випуску релізів](docs/RELEASE_PROCESS_UK.md)

**New: Code has been adapted for Ubuntu 24.04. See the ros2_jazzy branch for details.**
# 1. Introduction
This repository implements the ROS2 version of VINS-MONO, mainly including the following packages:
* **camera_model**
* **feature_tracker**
* **vins_estimator**
* **pose_graph**
* **benchmark_pubilsher**
* **ar_demo**
* **config_pkg**

**NOTE**: Since the **_get_package_share_directory_** command in ROS2 launch files can only locate packages in the _install_ directory instead of the _src_ directory like ROS1, we create a package called **_config_pkg_** to store the _config/_ and _support_files/_ folders from VINS-MONO.
 
![mh01](https://github.com/dongbo19/VINS-MONO-ROS2/blob/main/config_pkg/config/gif/vins_ros2_mh01.gif)
![mh02](https://github.com/dongbo19/VINS-MONO-ROS2/blob/main/config_pkg/config/gif/vins_ros2_mh02.gif)
# 2. Prerequisites
* System  
  * Ubuntu 24.04
  * ROS 2 Jazzy
* Libraries
  * OpenCV 4.6.0
  * [Ceres Solver](http://ceres-solver.org/installation.html) 2.2.0
  * Eigen 3.4.0
# 3. Build VINS-MONO-ROS2

## Docker (Windows 11, Linux, macOS)

Docker provides the supported Ubuntu 24.04 and ROS 2 Jazzy environment on any
host operating system. The complete Ukrainian guide is available in
[docs/DOCKER_UK.md](docs/DOCKER_UK.md). On Windows 11, install Docker Desktop,
enable the WSL 2 backend, then run these commands from PowerShell in the
repository directory:

```powershell
docker compose build
docker compose run --rm vins test
docker compose run --rm vins version
```

For an interactive ROS 2 shell:

```powershell
docker compose run --rm vins shell
```

To create and run the ARM64 development environment locally without compiling
VINS, use the ARM64 Compose override:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml build
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins uname -m
```

The expected architecture is `aarch64`. Docker Desktop uses ARM64 emulation on
an x86-64 Windows host; the resulting image can later be transferred to a
64-bit Raspberry Pi.

The source directory is mounted into the container. Docker named volumes retain
`build`, `install`, and `log`, so subsequent builds are incremental. To mount a
dataset read-only at `/data`, set `VINS_DATA_DIR` before starting the container:

```powershell
$env:VINS_DATA_DIR = "D:\datasets\EuRoC"
docker compose run --rm vins shell
```

Inside the container, a typical dataset run is:

```bash
ros2 launch feature_tracker vins_feature_tracker.launch.py
ros2 launch vins_estimator euroc.launch.py
ros2 bag play /data/MH_01_easy
```

RViz and direct camera/USB access require host-specific forwarding. The default
Docker workflow intentionally targets reproducible headless builds and tests.

Clone the repository and colcon build:  
```
cd $(PATH_TO_YOUR_ROS2_WS)/src
git clone https://github.com/dongbo19/VINS-MONO-ROS2.git
cd ..
colcon build
```
# 4. VINS-MONO-ROS2 on EuRoC datasets
## 4.1. ROS1 bag to ROS2 bag
Download [EuRoC datasets](https://projects.asl.ethz.ch/datasets/doku.php?id=kmavvisualinertialdatasets). However, the datasets are in ROS1 format. To run the code in ROS2, we need to first convert these datasets to ROS2 format. We can use [rosbags](https://pypi.org/project/rosbags/) for this purpose, which can convert ROS built-in messages between ROS1 and ROS2.  
## 4.2. Visual-inertial odometry and loop closure
All configuration files are in the package, **_config_pkg_**, so in launch files, the path to the EuRoC configuration files is found using **_get_package_share_directory('config_pkg')_**.  
Open three terminals, launch the feature_tracker, vins_estimator, rviz2, and ros2 bag. Take the MH01 for example
```
ros2 launch feature_tracker vins_feature_tracker.launch.py              # for feature tracking and rviz2
ros2 launch vins_estimator euroc.launch.py                              # for backend optimization and loop closure
ros2 bag play $(PATH_TO_YOUR_DATASET)/MH_01_easy                        # for ros2 bag
```
![mh05](https://github.com/dongbo19/VINS-MONO-ROS2/blob/main/config_pkg/config/gif/vins_ros2_mh05.gif)
![v101](https://github.com/dongbo19/VINS-MONO-ROS2/blob/main/config_pkg/config/gif/vins_ros2_v101.gif)
## 4.3. Visualize ground truch
First, take the MH01 for example, modifying the **'sequence_name'** in the launch file: 
**_benchmark_publisher/launch/benchmark_publisher.launch.py_**
```
sequence_name_arg = DeclareLaunchArgument(
    'sequence_name',
    default_value='MH_01_easy',
    description='Sequence name for the benchmark'
)
sequence_name = LaunchConfiguration('sequence_name')
```
**PS: After modifying the launch file, don't forget to run **_colcon build_** for this package again.**  
Then, open four terminals, launch the feature_tracker, vins_estimator, benchmark_mark, rviz2, and ros2 bag.
```
ros2 launch feature_tracker vins_feature_tracker.launch.py            # for feature tracking and rviz2
ros2 launch vins_estimator euroc.launch.py                            # for backend optimization and loop closure
ros2 launch benchmark_publisher benchmark_publisher.launch.py         # for benchmark
ros2 bag play $(PATH_TO_YOUR_DATASET)/MH_01_easy                      # for ros2 bag
```
![mh01_benchmark](https://github.com/dongbo19/VINS-MONO-ROS2/blob/main/config_pkg/config/gif/vins_ros2_benchmark_mh01.gif)
![mh02_benchmark](https://github.com/dongbo19/VINS-MONO-ROS2/blob/main/config_pkg/config/gif/vins_ros2_benchmark_mh02.gif)
## 4.4. AR Demo
Download the [bag file](https://www.dropbox.com/scl/fi/q18lot4bfs1fqrctclz7b/ar_box.bag?rlkey=16yrxnwnt2fcutwwzwhlevd1n&e=1&dl=0).  
Then open two terminals  
```
ros2 launch ar_demo 3dm_bag.launch.py               # for featuer tracking, backend optimization, ar demo and rviz2.
ros2 bag play $(PATH_TO_YOUR_DATASET)/ar_box        # for ros2 bag
```
![ar_demo](https://github.com/dongbo19/VINS-MONO-ROS2/blob/main/config_pkg/config/gif/vins_ros2_ar_demo.gif)
# 5. Run your own datasets
If you need to run your own collected datasets, please add your configuration files to the _config_pkg/config_ directory, and then modify the **_config_path_** in the launch files mentioned above to find your configuration file:  
```
config_path = PathJoinSubstitution([
    config_pkg_path,
    'config/$(YOUR_YAML_FILE)'
])
```
**PS: After modifying the launch files or config files, don't forget to run **_colcon build_** for those packages again.**  
# 6. Acknowledgements
We use ros1 version of [VINS MONO](https://github.com/HKUST-Aerial-Robotics/VINS-Mono),  [ceres solver](http://ceres-solver.org/installation.html) for non-linear optimization, [DBoW2](https://github.com/dorian3d/DBoW2) for loop detection, and a generic [camera model](https://github.com/hengli/camodocal). Also, we referred to parts of the implementations from [VINS-FUSION-ROS2](https://github.com/zinuok/VINS-Fusion-ROS2) and [vins-mono-ros2](https://github.com/hitzzq/vins-mono-ros2).

# 7. Release history
See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.

# 8. Licence
The source code is released under [GPLv3](https://www.gnu.org/licenses/) license.
