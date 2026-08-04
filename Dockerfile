ARG ROS_DISTRO=jazzy
FROM ros:${ROS_DISTRO}-ros-base AS dependencies

ARG ROS_DISTRO
ENV ROS_DISTRO=${ROS_DISTRO} \
    DEBIAN_FRONTEND=noninteractive \
    VINS_WS=/workspace

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        libboost-filesystem-dev \
        libboost-program-options-dev \
        libboost-system-dev \
        libceres-dev \
        libeigen3-dev \
        libopencv-dev \
        python3-colcon-common-extensions \
        python3-rosdep \
        ros-${ROS_DISTRO}-cv-bridge \
        ros-${ROS_DISTRO}-image-transport \
        ros-${ROS_DISTRO}-message-filters \
        ros-${ROS_DISTRO}-rviz2 \
        ros-${ROS_DISTRO}-tf2-ros \
    && rm -rf /var/lib/apt/lists/*

WORKDIR ${VINS_WS}

FROM dependencies AS development

COPY docker/entrypoint.sh /usr/local/bin/vins-entrypoint
COPY docker/bash_env.sh /usr/local/share/vins/bash_env.sh
RUN sed -i 's/\r$//' \
        /usr/local/bin/vins-entrypoint \
        /usr/local/share/vins/bash_env.sh \
    && chmod +x /usr/local/bin/vins-entrypoint

ENTRYPOINT ["/usr/local/bin/vins-entrypoint"]
CMD ["shell"]

FROM development AS build

COPY . ${VINS_WS}
RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && colcon build --merge-install --executor sequential

ENV BASH_ENV=/usr/local/share/vins/bash_env.sh

FROM build AS test

RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && source ${VINS_WS}/install/setup.bash \
    && colcon test --merge-install --event-handlers console_direct+ \
        --return-code-on-test-failure \
    && colcon test-result --verbose

FROM dependencies AS test-runtime

ARG PRODUCT_VERSION=0.0.0.0
ARG RELEASE_TAG=unreleased
ARG SOURCE_COMMIT=unknown

LABEL org.opencontainers.image.title="VINS-NEO Ubuntu test environment" \
      org.opencontainers.image.description="Ubuntu 24.04/Jazzy AMD64 test and dataset environment; not ARM64 release evidence" \
      org.opencontainers.image.source="https://github.com/Drone-Age/VINS-NEO" \
      org.opencontainers.image.version="${PRODUCT_VERSION}" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.drone-age.vins.release-tag="${RELEASE_TAG}" \
      org.drone-age.vins.platform="ubuntu-24.04-amd64" \
      org.drone-age.vins.evidence-class="development"

ENV VINS_PREFIX=/opt/vins \
    VINS_TOOLS=/opt/vins-neo/tools

COPY docker/test-runtime-entrypoint.sh /usr/local/bin/vins-test-entrypoint
COPY --from=test ${VINS_WS}/install/ ${VINS_PREFIX}/
COPY tools/dataset_e2e.py tools/dataset_e2e_monitor.py ${VINS_TOOLS}/
RUN sed -i 's/\r$//' /usr/local/bin/vins-test-entrypoint \
    && chmod +x \
        /usr/local/bin/vins-test-entrypoint \
        ${VINS_TOOLS}/dataset_e2e.py \
        ${VINS_TOOLS}/dataset_e2e_monitor.py

ENTRYPOINT ["/usr/local/bin/vins-test-entrypoint"]
CMD ["shell"]

FROM test AS deb-build

ARG PACKAGE_VERSION=1.0.2.0

RUN cp -a ${VINS_WS}/install /opt/vins

RUN package_arch="$(dpkg --print-architecture)" \
    && package_root="/tmp/vins-mono-ros2_${PACKAGE_VERSION}_${package_arch}" \
    && mkdir -p \
        "${package_root}/DEBIAN" \
        "${package_root}/opt" \
        "${package_root}/etc/profile.d" \
        /out \
    && cp -a /opt/vins "${package_root}/opt/vins" \
    && printf '%s\n' \
        'Package: vins-mono-ros2' \
        "Version: ${PACKAGE_VERSION}" \
        'Section: robotics' \
        'Priority: optional' \
        "Architecture: ${package_arch}" \
        'Maintainer: VINS-NEO-V1 maintainers' \
        "Depends: ros-${ROS_DISTRO}-ros-base, ros-${ROS_DISTRO}-cv-bridge, ros-${ROS_DISTRO}-image-transport, ros-${ROS_DISTRO}-message-filters, ros-${ROS_DISTRO}-tf2-ros, libboost-filesystem-dev, libboost-program-options-dev, libboost-system-dev, libceres-dev, libeigen3-dev, libopencv-dev" \
        'Description: VINS-MONO visual-inertial odometry for ROS 2' \
        ' ROS 2 overlay containing the VINS-MONO nodes, launch files,' \
        ' configuration, camera model, pose graph and benchmark tools.' \
        > "${package_root}/DEBIAN/control" \
    && printf '%s\n' \
        "# VINS-MONO ROS 2 overlay" \
        "[ -f /opt/ros/${ROS_DISTRO}/setup.sh ] && . /opt/ros/${ROS_DISTRO}/setup.sh" \
        '[ -f /opt/vins/setup.sh ] && . /opt/vins/setup.sh' \
        > "${package_root}/etc/profile.d/vins-mono-ros2.sh" \
    && chmod 0644 "${package_root}/etc/profile.d/vins-mono-ros2.sh" \
    && installed_size="$(du -sk "${package_root}" | cut -f1)" \
    && printf 'Installed-Size: %s\n' "${installed_size}" >> "${package_root}/DEBIAN/control" \
    && dpkg-deb --build --root-owner-group \
        "${package_root}" \
        "/out/vins-mono-ros2_${PACKAGE_VERSION}_${package_arch}.deb"

FROM scratch AS deb

COPY --from=deb-build /out/ /
