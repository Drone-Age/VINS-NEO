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
  --iros-version VERSION       upstream IROS release version
  --iros-deb-version VERSION   installed Debian package version
  --iros-asset-url URL         pinned Debian package download URL
  --iros-sha256 SHA256         checksum recorded in evidence
  --cv-bridge-ref SHA          pinned vision_opencv commit
  --opencv-version VERSION     required OpenCV pkg-config version

Optional:
  --install-dependencies       install Debian build dependencies with apt
  --install-test               install the generated package and smoke-test it
  --dataset-test               run the configured VINS dataset test runner
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
iros_asset_url=
iros_sha256=
cv_bridge_ref=
opencv_version=
install_dependencies=false
install_test=false
dataset_test=false
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
    --iros-asset-url) iros_asset_url=$2; shift 2 ;;
    --iros-sha256) iros_sha256=$2; shift 2 ;;
    --cv-bridge-ref) cv_bridge_ref=$2; shift 2 ;;
    --opencv-version) opencv_version=$2; shift 2 ;;
    --install-dependencies) install_dependencies=true; shift ;;
    --install-test) install_test=true; shift ;;
    --dataset-test) dataset_test=true; shift ;;
    --vins-config) vins_config=$2; shift 2 ;;
    --dataset) dataset=$2; shift 2 ;;
    --dataset-runner) dataset_runner=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for value_name in source_dir evidence_dir product_version release_tag source_commit \
  iros_version iros_deb_version iros_sha256 cv_bridge_ref opencv_version; do
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
[[ $iros_sha256 =~ ^[0-9a-f]{64}$ ]]
[[ $cv_bridge_ref =~ ^[0-9a-f]{40}$ ]]
[[ $iros_asset_url == \
  "https://github.com/Drone-Age/iros2_0/releases/download/v${iros_version}/iros2-0_${iros_deb_version}_arm64.deb" ]]

mkdir -p "$evidence_dir"
evidence_dir=$(realpath "$evidence_dir")
source_dir=$(realpath "$source_dir")
log_file="$evidence_dir/native-release.log"
exec > >(tee -a "$log_file") 2>&1

step() {
  printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local code=$?
  printf '\nFAILED exit=%s line=%s command=%q\n' \
    "$code" "${BASH_LINENO[0]:-unknown}" "${BASH_COMMAND:-unknown}" >&2
  exit "$code"
}
trap on_error ERR

step "Record invocation and environment"
printf '%q ' "$0" "$@" >"$evidence_dir/invocation.txt"
printf '\n' >>"$evidence_dir/invocation.txt"
{
  printf 'PRODUCT_VERSION=%s\n' "$product_version"
  printf 'RELEASE_TAG=%s\n' "$release_tag"
  printf 'SOURCE_COMMIT=%s\n' "$source_commit"
  printf 'IROS_VERSION=%s\n' "$iros_version"
  printf 'IROS_DEB_VERSION=%s\n' "$iros_deb_version"
  printf 'IROS_ASSET_URL=%s\n' "$iros_asset_url"
  printf 'IROS_SHA256=%s\n' "$iros_sha256"
  printf 'CV_BRIDGE_REF=%s\n' "$cv_bridge_ref"
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

for command in git cmake colcon pkg-config dpkg-deb sha256sum ldd; do
  command -v "$command" >/dev/null || fail "Required command is missing: $command"
done

if $install_dependencies; then
  step "Install native Debian build dependencies"
  sudo -n apt-get update
  sudo -n apt-get install -y --no-install-recommends \
    build-essential ca-certificates cmake curl git \
    libboost-filesystem-dev libboost-program-options-dev libboost-python-dev \
    libboost-system-dev libceres-dev libeigen3-dev libopencv-dev pkg-config \
    python3-colcon-bash python3-colcon-cmake python3-colcon-core \
    python3-colcon-library-path python3-colcon-output \
    python3-colcon-package-selection python3-colcon-parallel-executor \
    python3-colcon-python-setup-py python3-colcon-recursive-crawl \
    python3-colcon-ros python3-colcon-test-result python3-dev \
    libconsole-bridge-dev liblttng-ust-dev libssl-dev libtinyxml2-dev
fi

step "Install or verify the release-pinned IROS package"
installed_iros=$(dpkg-query -W -f='${Version}' iros2-0 2>/dev/null || true)
if [[ $installed_iros != "$iros_deb_version" ]]; then
  $install_dependencies ||
    fail "iros2-0 is '${installed_iros:-missing}'; expected $iros_deb_version"
  work_dir="${work_dir:-$evidence_dir/work}"
  iros_package="$work_dir/iros2-0_${iros_deb_version}_arm64.deb"
  mkdir -p "$work_dir"
  curl --fail --location --retry 3 \
    "$iros_asset_url" --output "$iros_package"
  printf '%s  %s\n' "$iros_sha256" "$iros_package" | sha256sum -c -
  [[ $(dpkg-deb -f "$iros_package" Package) == iros2-0 ]]
  [[ $(dpkg-deb -f "$iros_package" Version) == "$iros_deb_version" ]]
  [[ $(dpkg-deb -f "$iros_package" Architecture) == arm64 ]]
  sudo -n apt-get install -y "$iros_package"
fi

step "Verify IROS and native ABI"
[[ -f /opt/iros2_0/jazzy/setup.bash ]] || fail "IROS setup.bash is missing"
installed_iros=$(dpkg-query -W -f='${Version}' iros2-0)
[[ $installed_iros == "$iros_deb_version" ]] ||
  fail "iros2-0 is $installed_iros; expected $iros_deb_version"
source /opt/iros2_0/jazzy/setup.bash
installed_opencv=$(pkg-config --modversion opencv4)
[[ $installed_opencv == "$opencv_version" ]] ||
  fail "OpenCV is $installed_opencv; expected $opencv_version"
printf 'iros2-0=%s\nopencv4=%s\n' "$installed_iros" "$installed_opencv" |
  tee "$evidence_dir/native-dependencies.txt"

step "Verify source release metadata"
grep -Fq "project(vins_estimator VERSION $product_version)" \
  "$source_dir/vins_estimator/CMakeLists.txt"
grep -Fq "$release_tag" "$source_dir/vins_estimator/src/version.h.in"
grep -Fq "## [$release_tag]" "$source_dir/CHANGELOG.md"

work_dir="${work_dir:-$evidence_dir/work}"
cv_source="$work_dir/vision_opencv"
cv_build="$work_dir/cv_bridge-build"
vins_build="$work_dir/vins-build"
install_prefix=/opt/vins
mkdir -p "$work_dir"

step "Prepare a clean /opt/vins install prefix"
if [[ -e $install_prefix ]]; then
  backup="$evidence_dir/previous-opt-vins"
  [[ ! -e $backup ]] || fail "Backup path already exists: $backup"
  sudo -n mv "$install_prefix" "$backup"
fi
sudo -n install -d -o "$(id -u)" -g "$(id -g)" "$install_prefix"

step "Build pinned cv_bridge"
git clone --filter=blob:none --no-checkout \
  https://github.com/ros-perception/vision_opencv.git "$cv_source"
git -C "$cv_source" checkout "$cv_bridge_ref" -- cv_bridge
colcon build \
  --base-paths "$cv_source/cv_bridge" \
  --build-base "$cv_build" \
  --merge-install \
  --install-base "$install_prefix" \
  --executor sequential \
  --event-handlers console_direct+ \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib

step "Build VINS packages in Release mode"
source "$install_prefix/setup.bash"
colcon build \
  --base-paths "$source_dir" \
  --build-base "$vins_build" \
  --merge-install \
  --install-base "$install_prefix" \
  --executor sequential \
  --event-handlers console_direct+ \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib

step "Run colcon tests"
source "$install_prefix/setup.bash"
colcon test \
  --base-paths "$source_dir" \
  --build-base "$vins_build" \
  --install-base "$install_prefix" \
  --merge-install \
  --executor sequential \
  --event-handlers console_direct+
colcon test-result --test-result-base "$vins_build" --verbose |
  tee "$evidence_dir/colcon-test-result.txt"

step "Verify product version and ELF dependencies"
version_output=$(ros2 run vins_estimator vins_estimator --version)
expected_version="VINS-MONO ROS 2 $product_version ($release_tag)"
[[ $version_output == "$expected_version" ]] ||
  fail "Version output '$version_output' does not match '$expected_version'"
printf '%s\n' "$version_output" | tee "$evidence_dir/version.txt"

missing_file="$evidence_dir/ldd-missing.txt"
: >"$missing_file"
while IFS= read -r -d '' executable; do
  if file "$executable" | grep -q 'ELF'; then
    ldd "$executable" 2>&1 |
      awk -v file="$executable" '/not found/ {print file ": " $0}' \
      >>"$missing_file"
  fi
done < <(find "$install_prefix/bin" "$install_prefix/lib" \
  -type f -perm /111 -print0 2>/dev/null)
[[ ! -s $missing_file ]] || fail "Missing ELF dependencies were found"

step "Build and inspect Debian package"
package_root="$work_dir/vins-mono-ros2_${product_version}_arm64"
artifact="$evidence_dir/vins-mono-ros2_${product_version}_arm64.deb"
mkdir -p "$package_root/DEBIAN" "$package_root/opt" \
  "$package_root/etc/profile.d"
cp -a "$install_prefix" "$package_root/opt/vins"
cat >"$package_root/DEBIAN/control" <<EOF
Package: vins-mono-ros2
Version: $product_version
Section: robotics
Priority: optional
Architecture: arm64
Maintainer: VINS-NEO maintainers
Depends: iros2-0 (= $iros_deb_version), libboost-filesystem1.83.0, libboost-program-options1.83.0, libboost-python1.83.0, libboost-system1.83.0, libceres4, libopencv-core410, libopencv-calib3d410, libopencv-features2d410, libopencv-highgui410, libopencv-imgcodecs410, libopencv-imgproc410, libopencv-video410, python3
Description: VINS-NEO visual-inertial odometry for ROS 2 Jazzy
 Debian 13 ARM64 overlay built against the IROS2_0 Jazzy underlay
 and the Raspberry Pi OS Trixie system ABI.
EOF
cat >"$package_root/etc/profile.d/vins-mono-ros2.sh" <<'EOF'
# VINS-NEO ROS 2 overlay
[ -f /opt/iros2_0/jazzy/setup.sh ] && . /opt/iros2_0/jazzy/setup.sh
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
dpkg-deb -f "$artifact" Depends | grep -Fq "iros2-0 (= $iros_deb_version)"
sha256sum "$artifact" | tee "$artifact.sha256"

if $install_test; then
  step "Install generated package and run ROS smoke test"
  sudo -n apt-get install -y "$artifact"
  dpkg-query -W -f='${Status}\n' vins-mono-ros2 |
    grep -Fx 'install ok installed'
  source /opt/iros2_0/jazzy/setup.bash
  source /opt/vins/setup.bash
  ros2 pkg prefix vins_estimator
  ros2 pkg prefix feature_tracker
  [[ $(ros2 run vins_estimator vins_estimator --version) == "$expected_version" ]]
fi

if $dataset_test; then
  step "Run dataset test"
  [[ $install_test == true ]] ||
    fail "--dataset-test requires --install-test"
  [[ -f $vins_config ]] || fail "VINS config does not exist: $vins_config"
  [[ -f $dataset_runner ]] ||
    fail "Dataset runner does not exist: $dataset_runner"
  bag=$dataset
  [[ -d $bag ]] && bag="$bag/data.bag"
  [[ -e $bag ]] || fail "Dataset bag does not exist: $bag"
  python3 "$dataset_runner" --ros2 \
    --config "$vins_config" \
    --bag "$bag" \
    --ros-setup /opt/iros2_0/jazzy/setup.bash \
    --vins-setup /opt/vins/setup.bash |
    tee "$evidence_dir/dataset-test.txt"
fi

step "Native release gate completed"
printf 'PASS\n' | tee "$evidence_dir/status.txt"
