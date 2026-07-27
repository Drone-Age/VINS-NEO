#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: native-release.sh OPTIONS

Required:
  --source DIR                 exported VINS source tree
  --evidence DIR               output directory for logs and artifacts
  --version VERSION            MAJOR.MINOR.FEATURE.PATCH
  --tag TAG                    vMAJOR_MINOR_FEATURE_PATCH
  --commit SHA                 source commit recorded in evidence
  --iros-version VERSION       iros2j package-line version
  --iros-deb-version VERSION   installed Debian package version
  --iros-source-tag TAG        immutable iros2j source/release tag
  --iros-source-commit SHA     immutable iros2j source commit
  --iros-asset-url URL         signed iros2j APT snapshot URL
  --iros-sha256 SHA256         checksum recorded in evidence
  --iros-packages CSV          exact iros2j Debian package closure
  --iros-runtime-packages CSV  runtime subset for VINS Debian Depends
  --imavros-version VERSION    compatible iMAVROS product version
  --imavros-deb-version VER    compatible iMAVROS Debian version
  --imavros-tag TAG            immutable iMAVROS release tag
  --imavros-commit SHA         immutable iMAVROS release commit
  --imavros-prefix DIR         iMAVROS runtime prefix
  --opencv-version VERSION     required OpenCV pkg-config version

Optional:
  --install-dependencies       install Debian build dependencies with apt
  --install-test               install the generated package and smoke-test it
  --integration-test           verify iros2j -> iMAVROS -> VINS activation
  --dataset-test               run the configured VINS dataset test runner
  --skip-tests                 build and package without test execution
  --vins-config FILE           VINS YAML used by the dataset test
  --dataset PATH               bag file or directory containing data.bag
  --dataset-runner FILE        vins_test.py path
EOF
}

source_dir=
evidence_dir=
product_version=
release_tag=
source_commit=
iros_version=
iros_deb_version=
iros_source_tag=
iros_source_commit=
iros_asset_url=
iros_sha256=
iros_packages_csv=
iros_runtime_packages_csv=
imavros_version=
imavros_deb_version=
imavros_tag=
imavros_commit=
imavros_prefix=
opencv_version=
install_dependencies=false
install_test=false
integration_test=false
dataset_test=false
skip_tests=false
vins_config=
dataset=
dataset_runner=

while (($#)); do
  case "$1" in
    --source) source_dir=$2; shift 2 ;;
    --evidence) evidence_dir=$2; shift 2 ;;
    --version) product_version=$2; shift 2 ;;
    --tag) release_tag=$2; shift 2 ;;
    --commit) source_commit=$2; shift 2 ;;
    --iros-version) iros_version=$2; shift 2 ;;
    --iros-deb-version) iros_deb_version=$2; shift 2 ;;
    --iros-source-tag) iros_source_tag=$2; shift 2 ;;
    --iros-source-commit) iros_source_commit=$2; shift 2 ;;
    --iros-asset-url) iros_asset_url=$2; shift 2 ;;
    --iros-sha256) iros_sha256=$2; shift 2 ;;
    --iros-packages) iros_packages_csv=$2; shift 2 ;;
    --iros-runtime-packages) iros_runtime_packages_csv=$2; shift 2 ;;
    --imavros-version) imavros_version=$2; shift 2 ;;
    --imavros-deb-version) imavros_deb_version=$2; shift 2 ;;
    --imavros-tag) imavros_tag=$2; shift 2 ;;
    --imavros-commit) imavros_commit=$2; shift 2 ;;
    --imavros-prefix) imavros_prefix=$2; shift 2 ;;
    --opencv-version) opencv_version=$2; shift 2 ;;
    --install-dependencies) install_dependencies=true; shift ;;
    --install-test) install_test=true; shift ;;
    --integration-test) integration_test=true; shift ;;
    --dataset-test) dataset_test=true; shift ;;
    --skip-tests) skip_tests=true; shift ;;
    --vins-config) vins_config=$2; shift 2 ;;
    --dataset) dataset=$2; shift 2 ;;
    --dataset-runner) dataset_runner=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for value_name in source_dir evidence_dir product_version release_tag source_commit \
  iros_version iros_deb_version iros_source_tag iros_source_commit \
  iros_sha256 iros_packages_csv iros_runtime_packages_csv \
  imavros_version imavros_deb_version \
  imavros_tag imavros_commit imavros_prefix opencv_version; do
  if [[ -z ${!value_name} ]]; then
    printf 'Required value is empty: %s\n' "$value_name" >&2
    exit 2
  fi
done

[[ -n $iros_asset_url ]] || {
  printf 'Required value is empty: iros_asset_url\n' >&2
  exit 2
}

[[ $product_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ $release_tag =~ ^v[0-9]+_[0-9]{2}_[0-9]{2}_[0-9]{2}$ ]]
[[ $source_commit =~ ^[0-9a-f]{40}$ ]]
[[ $iros_source_tag =~ ^v2\.1\.[0-9]+\.[0-9]+$ ]]
[[ $iros_source_tag == "v2.${iros_version}" ]]
[[ $iros_source_commit =~ ^[0-9a-f]{40}$ ]]
[[ $iros_sha256 =~ ^[0-9a-f]{64}$ ]]
[[ $imavros_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ $imavros_tag == "v${imavros_version}" ]]
[[ $imavros_deb_version == "${imavros_version}-1+deb13" ]]
[[ $imavros_commit =~ ^[0-9a-f]{40}$ ]]
[[ $imavros_prefix == /opt/imavros ]]
[[ $iros_asset_url == \
  "https://github.com/Drone-Age/iros2_0/releases/download/${iros_source_tag}/iros2j-apt_trixie_arm64.tar.gz" ]]

IFS=',' read -r -a iros_packages <<<"$iros_packages_csv"
IFS=',' read -r -a iros_runtime_packages <<<"$iros_runtime_packages_csv"
((${#iros_packages[@]} > 0))
for package in "${iros_packages[@]}"; do
  [[ $package =~ ^iros2j-[a-z0-9][a-z0-9+.-]+$ ]] || {
    printf 'Invalid iros2j package name: %s\n' "$package" >&2
    exit 2
  }
done
for package in "${iros_runtime_packages[@]}"; do
  [[ " ${iros_packages[*]} " == *" $package "* ]] || {
    printf 'Runtime package is absent from the full closure: %s\n' \
      "$package" >&2
    exit 2
  }
done

mkdir -p "$evidence_dir"
evidence_dir=$(realpath "$evidence_dir")
source_dir=$(realpath "$source_dir")
log_file="$evidence_dir/native-release.log"
exec > >(tee -a "$log_file") 2>&1
test_report="$evidence_dir/test-results.tsv"
run_started_at=$(date --iso-8601=seconds)
current_test_id=
current_test_target=
current_test_command=
printf 'test_id\tresult\tstarted_at\tfinished_at\thost\ttarget\tcommand\tevidence\treason\tmissing_component\trequirement_effect\n' \
  >"$test_report"

step() {
  printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

record_result() {
  local test_id=$1 result=$2 target=$3 command=$4 evidence=$5
  local reason=${6:-} effect=${7:-satisfied}
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t\t%s\n' \
    "$test_id" "$result" "$run_started_at" "$(date --iso-8601=seconds)" \
    "$(hostname)" "$target" "$command" "$evidence" "$reason" "$effect" \
    >>"$test_report"
  current_test_id=
}

apt_config_active=false
apt_source=/etc/apt/sources.list.d/iros2j-vins-release.list
apt_keyring=/usr/share/keyrings/iros2j-vins-release.gpg
cleanup_system_apt() {
  if $apt_config_active; then
    sudo -n rm -f -- "$apt_source" "$apt_keyring" || true
    apt_config_active=false
  fi
}

source_setup() {
  local setup_file=$1
  set +u
  # ROS/colcon setup scripts may read optional variables such as COLCON_TRACE.
  source "$setup_file"
  set -u
}

on_error() {
  local code=$?
  if [[ -n ${current_test_id:-} ]]; then
    record_result "$current_test_id" FAIL "$current_test_target" \
      "$current_test_command" "$log_file" "exit=$code" blocked
  fi
  printf '\nFAILED exit=%s line=%s command=%q\n' \
    "$code" "${BASH_LINENO[0]:-unknown}" "${BASH_COMMAND:-unknown}" >&2
  exit "$code"
}
trap on_error ERR
trap cleanup_system_apt EXIT

current_test_id=native_platform
current_test_target="Raspberry Pi 5 Debian 13 ARM64"
current_test_command="native platform identity and toolchain checks"
step "Record invocation and environment"
printf '%q ' "$0" "$@" >"$evidence_dir/invocation.txt"
printf '\n' >>"$evidence_dir/invocation.txt"
{
  printf 'PRODUCT_VERSION=%s\n' "$product_version"
  printf 'RELEASE_TAG=%s\n' "$release_tag"
  printf 'SOURCE_COMMIT=%s\n' "$source_commit"
  printf 'IROS_VERSION=%s\n' "$iros_version"
  printf 'IROS_DEB_VERSION=%s\n' "$iros_deb_version"
  printf 'IROS_SOURCE_TAG=%s\n' "$iros_source_tag"
  printf 'IROS_SOURCE_COMMIT=%s\n' "$iros_source_commit"
  printf 'IROS_ASSET_URL=%s\n' "$iros_asset_url"
  printf 'IROS_SHA256=%s\n' "$iros_sha256"
  printf 'IROS_PACKAGES=%s\n' "$iros_packages_csv"
  printf 'IROS_RUNTIME_PACKAGES=%s\n' "$iros_runtime_packages_csv"
  printf 'IMAVROS_VERSION=%s\n' "$imavros_version"
  printf 'IMAVROS_DEB_VERSION=%s\n' "$imavros_deb_version"
  printf 'IMAVROS_TAG=%s\n' "$imavros_tag"
  printf 'IMAVROS_COMMIT=%s\n' "$imavros_commit"
  printf 'IMAVROS_PREFIX=%s\n' "$imavros_prefix"
  printf 'OPENCV_VERSION=%s\n' "$opencv_version"
} >"$evidence_dir/release.env"

uname -a | tee "$evidence_dir/uname.txt"
cat /etc/os-release | tee "$evidence_dir/os-release.txt"
dpkg --print-architecture | tee "$evidence_dir/debian-architecture.txt"
cmake --version | tee "$evidence_dir/cmake-version.txt"
c++ --version | tee "$evidence_dir/compiler-version.txt"

[[ $(uname -m) == aarch64 ]] || fail "uname -m is not aarch64"
[[ $(dpkg --print-architecture) == arm64 ]] ||
  fail "Debian architecture is not arm64"
grep -Fq 'VERSION_ID="13"' /etc/os-release ||
  fail "Debian/Raspberry Pi OS 13 is required"
[[ ! -e /.dockerenv ]] || fail "Docker is not a native release environment"

for command in git cmake colcon pkg-config dpkg-deb sha256sum ldd curl tar gpg; do
  command -v "$command" >/dev/null || fail "Required command is missing: $command"
done
record_result native_platform PASS "$current_test_target" \
  "$current_test_command" "$evidence_dir/uname.txt"

if $install_dependencies; then
  step "Install native Debian build dependencies"
  sudo -n apt-get update
  sudo -n apt-get install -y --no-install-recommends \
    build-essential ca-certificates cmake curl git gnupg \
    libboost-filesystem-dev libboost-program-options-dev libboost-python-dev \
    libboost-system-dev libceres-dev libeigen3-dev libopencv-dev pkg-config \
    python3-colcon-bash python3-colcon-cmake python3-colcon-core \
    python3-colcon-library-path python3-colcon-output \
    python3-colcon-package-selection python3-colcon-parallel-executor \
    python3-colcon-python-setup-py python3-colcon-recursive-crawl \
    python3-colcon-ros python3-colcon-test-result python3-dev \
    libconsole-bridge-dev liblttng-ust-dev libssl-dev libtinyxml2-dev
fi

current_test_id=iros2j_runtime
current_test_target="iros2j $iros_version at /opt/iros2j"
current_test_command="verify signed APT snapshot and exact iros2j package closure"
step "Install or verify the release-pinned signed iros2j APT snapshot"
work_dir="${work_dir:-$evidence_dir/work}"
mkdir -p "$work_dir"
if dpkg-query -W -f='${db:Status-Status}' iros2-0 2>/dev/null |
  grep -Fxq installed; then
  fail "Obsolete iros2-0 is installed"
fi
[[ ! -e /opt/iros2_0 ]] || fail "Obsolete /opt/iros2_0 prefix exists"

iros_packages_valid=true
for package in "${iros_packages[@]}"; do
  installed_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)
  [[ $installed_version == "$iros_deb_version" ]] ||
    iros_packages_valid=false
done

if ! $iros_packages_valid; then
  $install_dependencies ||
    fail "Exact iros2j dependency closure is not installed"
  iros_archive="$work_dir/iros2j-apt_trixie_arm64.tar.gz"
  iros_apt_root="$work_dir/iros2j-apt"
  curl --fail --location --retry 3 \
    "$iros_asset_url" --output "$iros_archive"
  printf '%s  %s\n' "$iros_sha256" "$iros_archive" | sha256sum -c -
  mkdir -p "$iros_apt_root"
  tar -xzf "$iros_archive" -C "$iros_apt_root"
  iros_repository="$iros_apt_root/apt-repository"
  [[ -f $iros_repository/iros2j-archive-keyring.asc ]] ||
    fail "Signed iros2j APT key is missing from the snapshot"
  gpg --dearmor <"$iros_repository/iros2j-archive-keyring.asc" \
    >"$work_dir/iros2j-vins-release.gpg"
  sudo -n install -m 0644 "$work_dir/iros2j-vins-release.gpg" "$apt_keyring"
  printf 'deb [arch=arm64 signed-by=%s] file:%s trixie main\n' \
    "$apt_keyring" "$(realpath "$iros_repository")" |
    sudo -n tee "$apt_source" >/dev/null
  apt_config_active=true
  sudo -n apt-get update
  sudo -n apt-get install -y "${iros_packages[@]}"
  cleanup_system_apt
fi

step "Verify iros2j dependency closure and native ABI"
[[ -f /opt/iros2j/setup.bash ]] || fail "iROS2j setup.bash is missing"
for package in "${iros_packages[@]}"; do
  installed_version=$(dpkg-query -W -f='${Version}' "$package")
  [[ $installed_version == "$iros_deb_version" ]] ||
    fail "$package is $installed_version; expected $iros_deb_version"
  printf '%s=%s\n' "$package" "$installed_version"
done | tee "$evidence_dir/iros2j-packages.txt"
source_setup /opt/iros2j/setup.bash
[[ $(ros2 pkg prefix cv_bridge) == /opt/iros2j* ]] ||
  fail "cv_bridge does not resolve under /opt/iros2j"
installed_opencv=$(pkg-config --modversion opencv4)
[[ $installed_opencv == "$opencv_version" ]] ||
  fail "OpenCV is $installed_opencv; expected $opencv_version"
printf 'iros2j=%s\nsource_tag=%s\nsource_commit=%s\nopencv4=%s\n' \
  "$iros_deb_version" "$iros_source_tag" "$iros_source_commit" "$installed_opencv" |
  tee "$evidence_dir/native-dependencies.txt"
record_result iros2j_runtime PASS "$current_test_target" \
  "$current_test_command" "$evidence_dir/iros2j-packages.txt"

current_test_id=release_metadata
current_test_target="VINS-NEO $product_version"
current_test_command="verify source version, tag, changelog, and package.xml metadata"
step "Verify source release metadata"
grep -Fq "project(vins_estimator VERSION $product_version)" \
  "$source_dir/vins_estimator/CMakeLists.txt"
grep -Fq "$release_tag" "$source_dir/vins_estimator/src/version.h.in"
grep -Fq "## [$release_tag]" "$source_dir/CHANGELOG.md"
ros_package_version=${product_version%.*}
while IFS= read -r package_xml; do
  grep -Fq "<version>${ros_package_version}</version>" "$package_xml" ||
    fail "$package_xml does not use ROS package version $ros_package_version"
done < <(find "$source_dir" -name package.xml -type f -print)
record_result release_metadata PASS "$current_test_target" \
  "$current_test_command" "$source_dir/config/releases/$release_tag.env"

work_dir="${work_dir:-$evidence_dir/work}"
vins_build="$work_dir/vins-build"
install_prefix=/opt/vins
mkdir -p "$work_dir"

step "Prepare isolated native build dependency sysroot"
build_sysroot="$work_dir/build-sysroot"
build_debs="$work_dir/build-debs"
mkdir -p "$build_sysroot" "$build_debs"
build_dependency_packages=(
  libblas-dev
  libblas3
  libboost-filesystem1.83-dev
  libboost-program-options1.83-dev
  libboost-system1.83-dev
  libceres-dev
  libceres4t64
  libgflags-dev
  libgflags2.2
  libgoogle-glog-dev
  libgoogle-glog0v6t64
  liblapack-dev
  liblapack3
  libsuitesparse-dev
)
(
  cd "$build_debs"
  apt-get download "${build_dependency_packages[@]}"
)
for build_deb in "$build_debs"/*.deb; do
  dpkg-deb -x "$build_deb" "$build_sysroot"
  dpkg-deb -f "$build_deb" Package Version
done | tee "$evidence_dir/build-sysroot-packages.txt"
export CMAKE_PREFIX_PATH="$build_sysroot/usr${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export CMAKE_LIBRARY_PATH="$build_sysroot/usr/lib/aarch64-linux-gnu:$build_sysroot/usr/lib/aarch64-linux-gnu/blas:$build_sysroot/usr/lib/aarch64-linux-gnu/lapack${CMAKE_LIBRARY_PATH:+:$CMAKE_LIBRARY_PATH}"
export CPLUS_INCLUDE_PATH="$build_sysroot/usr/include${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
export LIBRARY_PATH="$build_sysroot/usr/lib/aarch64-linux-gnu:$build_sysroot/usr/lib/aarch64-linux-gnu/blas:$build_sysroot/usr/lib/aarch64-linux-gnu/lapack${LIBRARY_PATH:+:$LIBRARY_PATH}"
export PKG_CONFIG_PATH="$build_sysroot/usr/lib/aarch64-linux-gnu/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

step "Prepare a clean /opt/vins install prefix"
if [[ -e $install_prefix ]]; then
  backup="$evidence_dir/previous-opt-vins"
  [[ ! -e $backup ]] || fail "Backup path already exists: $backup"
  sudo -n mv "$install_prefix" "$backup"
fi
sudo -n install -d -o "$(id -u)" -g "$(id -g)" "$install_prefix"

current_test_id=release_build
current_test_target="/opt/vins"
current_test_command="colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release"
step "Build VINS packages in Release mode"
colcon build \
  --base-paths "$source_dir" \
  --build-base "$vins_build" \
  --merge-install \
  --install-base "$install_prefix" \
  --executor sequential \
  --event-handlers console_direct+ \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib
record_result release_build PASS "$current_test_target" \
  "$current_test_command" "$log_file"

if ! $skip_tests; then
  current_test_id=colcon_test
  current_test_target="VINS ROS packages"
  current_test_command="colcon test && colcon test-result --verbose"
  step "Run colcon tests"
  source_setup "$install_prefix/setup.bash"
  colcon test \
    --base-paths "$source_dir" \
    --build-base "$vins_build" \
    --install-base "$install_prefix" \
    --merge-install \
    --executor sequential \
    --event-handlers console_direct+
  colcon test-result --test-result-base "$vins_build" --verbose |
    tee "$evidence_dir/colcon-test-result.txt"
  record_result colcon_test PASS "$current_test_target" \
    "$current_test_command" "$evidence_dir/colcon-test-result.txt"
else
  step "Skip tests by release operator decision"
  printf 'NOT_RUN\n' | tee "$evidence_dir/test-status.txt"
  record_result colcon_test NOT_RUN "VINS ROS packages" \
    "colcon test && colcon test-result --verbose" \
    "$evidence_dir/test-status.txt" "operator supplied --skip-tests" blocked
fi

step "Verify product version and ELF dependencies"
version_output=$(ros2 run vins_estimator vins_estimator --version)
expected_version="VINS-MONO ROS 2 $product_version ($release_tag)"
[[ $version_output == "$expected_version" ]] ||
  fail "Version output '$version_output' does not match '$expected_version'"
printf '%s\n' "$version_output" | tee "$evidence_dir/version.txt"

missing_file="$evidence_dir/ldd-missing.txt"
: >"$missing_file"
elf_search_paths=()
for candidate in "$install_prefix/bin" "$install_prefix/lib"; do
  [[ ! -d $candidate ]] || elf_search_paths+=("$candidate")
done
while IFS= read -r -d '' executable; do
  if file "$executable" | grep -q 'ELF'; then
    ldd "$executable" 2>&1 |
      awk -v file="$executable" '/not found/ {print file ": " $0}' \
      >>"$missing_file"
  fi
done < <(find "${elf_search_paths[@]}" -type f -perm /111 -print0)
[[ ! -s $missing_file ]] || fail "Missing ELF dependencies were found"

step "Verify /opt/vins owns only VINS packages"
[[ ! -e /opt/vins/share/cv_bridge ]] ||
  fail "/opt/vins contains a private cv_bridge payload"
for ros_package in ament_cmake ament_index_cpp cv_bridge geometry_msgs \
  image_transport message_filters nav_msgs rclcpp rcpputils rmw_fastrtps_cpp \
  rviz2 sensor_msgs std_msgs tf2 tf2_ros visualization_msgs; do
  package_prefix=$(ros2 pkg prefix "$ros_package")
  [[ $package_prefix == /opt/iros2j* ]] ||
    fail "$ros_package resolves to $package_prefix, not /opt/iros2j"
done
find /opt/vins -type f -o -type l | sort >"$evidence_dir/vins-owned-files.txt"

current_test_id=debian_package
current_test_target="vins-mono-ros2 ARM64 Debian package"
current_test_command="dpkg-deb build and metadata/ownership/ELF audit"
step "Build and inspect Debian package"
package_root="$work_dir/vins-mono-ros2_${product_version}_arm64"
artifact="$evidence_dir/vins-mono-ros2_${product_version}_arm64.deb"
mkdir -p "$package_root/DEBIAN" "$package_root/opt" \
  "$package_root/etc/profile.d"
cp -a "$install_prefix" "$package_root/opt/vins"
iros_depends=
for package in "${iros_runtime_packages[@]}"; do
  iros_depends+="${package} (= ${iros_deb_version}), "
done
iros_depends=${iros_depends%, }
cat >"$package_root/DEBIAN/control" <<EOF
Package: vins-mono-ros2
Version: $product_version
Section: robotics
Priority: optional
Architecture: arm64
Maintainer: VINS-NEO maintainers
Depends: $iros_depends, libboost-filesystem1.83.0, libboost-program-options1.83.0, libboost-python1.83.0, libboost-system1.83.0, libceres4, libopencv-core410, libopencv-calib3d410, libopencv-features2d410, libopencv-highgui410, libopencv-imgcodecs410, libopencv-imgproc410, libopencv-video410, python3
Description: VINS-NEO visual-inertial odometry for ROS 2 Jazzy
 Debian 13 ARM64 overlay built against the split-package iros2j Jazzy underlay
 and the Raspberry Pi OS Trixie system ABI.
EOF
cat >"$package_root/etc/profile.d/vins-mono-ros2.sh" <<'EOF'
# VINS-NEO ROS 2 overlay
[ -f /opt/iros2j/setup.sh ] && . /opt/iros2j/setup.sh
[ -f /opt/imavros/setup.sh ] && . /opt/imavros/setup.sh
[ -f /opt/vins/setup.sh ] && . /opt/vins/setup.sh
EOF
chmod 0644 "$package_root/etc/profile.d/vins-mono-ros2.sh"
installed_size=$(du -sk "$package_root" | cut -f1)
printf 'Installed-Size: %s\n' "$installed_size" >>"$package_root/DEBIAN/control"
dpkg-deb --build --root-owner-group "$package_root" "$artifact"
dpkg-deb --info "$artifact" | tee "$evidence_dir/package-info.txt"
dpkg-deb --contents "$artifact" >"$evidence_dir/package-contents.txt"
[[ $(dpkg-deb -f "$artifact" Version) == "$product_version" ]]
[[ $(dpkg-deb -f "$artifact" Architecture) == arm64 ]]
package_dependencies=$(dpkg-deb -f "$artifact" Depends)
for package in "${iros_runtime_packages[@]}"; do
  grep -Fq "$package (= $iros_deb_version)" <<<"$package_dependencies"
done
! grep -Fq "iros2-0" <<<"$package_dependencies"
! dpkg-deb --contents "$artifact" | grep -Eq '/opt/vins/.*/cv_bridge|/opt/vins/share/cv_bridge'
sha256sum "$artifact" | tee "$artifact.sha256"
record_result debian_package PASS "$current_test_target" \
  "$current_test_command" "$evidence_dir/package-info.txt"

if $install_test; then
  current_test_id=clean_install
  current_test_target="installed VINS package at /opt/vins"
  current_test_command="apt install generated package and VINS smoke"
  step "Install generated package and run ROS smoke test"
  sudo -n apt-get install -y "$artifact"
  dpkg-query -W -f='${Status}\n' vins-mono-ros2 |
    grep -Fx 'install ok installed'
  source_setup /opt/iros2j/setup.bash
  source_setup /opt/vins/setup.bash
  ros2 pkg prefix vins_estimator
  ros2 pkg prefix feature_tracker
  [[ $(ros2 run vins_estimator vins_estimator --version) == "$expected_version" ]]
  record_result clean_install PASS "$current_test_target" \
    "$current_test_command" "$evidence_dir/version.txt"
else
  record_result clean_install NOT_RUN "installed VINS package at /opt/vins" \
    "apt install generated package and VINS smoke" none \
    "--install-test was not supplied" blocked
fi

if $integration_test; then
  current_test_id=runtime_integration
  current_test_target="iros2j -> iMAVROS -> VINS"
  current_test_command="clean-shell Fast DDS activation smoke"
  step "Verify clean-shell iros2j -> iMAVROS -> VINS activation"
  [[ $install_test == true ]] ||
    fail "--integration-test requires --install-test"
  installed_imavros=$(dpkg-query -W -f='${Version}' imavros 2>/dev/null || true)
  [[ $installed_imavros == "$imavros_deb_version" ]] ||
    fail "imavros is '${installed_imavros:-missing}'; expected $imavros_deb_version"
  [[ -f $imavros_prefix/setup.bash ]] ||
    fail "iMAVROS setup.bash is missing at $imavros_prefix"
  env -i HOME="$HOME" PATH=/usr/bin:/bin \
    IMAVROS_VERSION="$imavros_version" IMAVROS_TAG="$imavros_tag" \
    IMAVROS_COMMIT="$imavros_commit" \
    bash --noprofile --norc -e -c "
      source /opt/iros2j/setup.bash
      source '$imavros_prefix/setup.bash'
      source /opt/vins/setup.bash
      test \"\${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}\" = rmw_fastrtps_cpp
      test \"\$(ros2 pkg prefix cv_bridge)\" = /opt/iros2j/cv_bridge
      test \"\$(ros2 pkg prefix mavros)\" = '$imavros_prefix/mavros'
      test \"\$(ros2 pkg prefix vins_estimator)\" = /opt/vins
      RMW_IMPLEMENTATION=rmw_fastrtps_cpp ros2 topic list >/dev/null
    " | tee "$evidence_dir/integration-smoke.txt"
  record_result runtime_integration PASS "$current_test_target" \
    "$current_test_command" "$evidence_dir/integration-smoke.txt"
else
  record_result runtime_integration NOT_RUN "iros2j -> iMAVROS -> VINS" \
    "clean-shell Fast DDS activation smoke" none \
    "--integration-test was not supplied" blocked
fi

if $dataset_test; then
  current_test_id=vins_dataset
  current_test_target="configured VINS dataset"
  current_test_command="vins_test.py controlled dataset gate"
  step "Run dataset test"
  [[ $install_test == true ]] ||
    fail "--dataset-test requires --install-test"
  [[ -f $vins_config ]] || fail "VINS config does not exist: $vins_config"
  [[ -f $dataset_runner ]] ||
    fail "Dataset runner does not exist: $dataset_runner"
  bag=$dataset
  [[ -d $bag ]] && bag="$bag/data.bag"
  [[ -e $bag ]] || fail "Dataset bag does not exist: $bag"
  dataset_config="$work_dir/dataset-config.yaml"
  dataset_test_json="$work_dir/dataset-test.json"
  cp "$vins_config" "$dataset_config"
  cat >"$dataset_test_json" <<'EOF'
{
  "objective": "delta_xy",
  "parameters": {
    "acc_n": {
      "step": 0.001,
      "min_step": 0.001,
      "max_fails": 0,
      "max_trials": 1,
      "max_step_reductions": 0
    }
  },
  "test": {
    "repeats": 1,
    "aggregation": "median"
  }
}
EOF
  python3 "$dataset_runner" --ros2 -param acc_n \
    --test-json "$dataset_test_json" \
    --config "$dataset_config" \
    --bag "$bag" \
    --ros-setup /opt/iros2j/setup.bash \
    --vins-setup /opt/vins/setup.bash |
    tee "$evidence_dir/dataset-test.txt"
  record_result vins_dataset PASS "$current_test_target" \
    "$current_test_command" "$evidence_dir/dataset-test.txt"
else
  record_result vins_dataset NOT_RUN "configured VINS dataset" \
    "vins_test.py controlled dataset gate" none \
    "--dataset-test was not supplied" blocked
fi

step "Native release gate completed"
printf 'PASS\n' | tee "$evidence_dir/status.txt"
