cmake_minimum_required(VERSION 3.5)
project(vins_estimator VERSION 1.0.3.0)

set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-Wextra -Wpedantic)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rcpputils REQUIRED)
find_package(std_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(visualization_msgs REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(tf2 REQUIRED)
find_package(tf2_ros REQUIRED)
find_package(cv_bridge REQUIRED)
find_package(camera_model REQUIRED)
find_package(image_transport REQUIRED)

find_package(OpenCV 4 REQUIRED)

find_package(Ceres REQUIRED)

configure_file(
  src/version.h.in
  ${CMAKE_CURRENT_BINARY_DIR}/generated/version.h
  @ONLY
)

include_directories(${CERES_INCLUDE_DIRS})
include_directories(${CMAKE_CURRENT_BINARY_DIR}/generated)

include_directories("../camera_models/include")

set(CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/cmake)
find_package(Eigen3)
include_directories(
  ${EIGEN3_INCLUDE_DIR}
)

add_executable(vins_estimator
    src/estimator_node.cpp
    src/parameters.cpp
    src/estimator.cpp
    src/feature_manager.cpp
    src/factor/pose_local_parameterization.cpp
    src/factor/projection_factor.cpp
    src/factor/projection_td_factor.cpp
    src/factor/marginalization_factor.cpp
    src/utility/utility.cpp
    src/utility/visualization.cpp
    src/utility/CameraPoseVisualization.cpp
    src/initial/solve_5pts.cpp
    src/initial/initial_aligment.cpp
    src/initial/initial_sfm.cpp
    src/initial/initial_ex_rotation.cpp
    )

ament_target_dependencies(vins_estimator rclcpp rcpputils std_msgs sensor_msgs visualization_msgs geometry_msgs nav_msgs tf2 tf2_ros cv_bridge camera_model image_transport)

target_link_libraries(vins_estimator ${OpenCV_LIBS} ${CERES_LIBRARIES}) 

# Install nodes
install(
  TARGETS vins_estimator
  DESTINATION lib/${PROJECT_NAME}
)

install(
  DIRECTORY launch
  DESTINATION share/${PROJECT_NAME}
)

if(BUILD_TESTING)
  find_package(ament_cmake_test REQUIRED)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  set(REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
  set(IROS2J_MIGRATION_TESTS
    test_exact_runtime_identity
    test_iros2j_dependency_closure_is_exact_and_sorted
    test_private_cv_bridge_build_is_removed
    test_active_runtime_paths_use_iros2j
    test_package_audit_rejects_legacy_and_duplicate_payload
    test_current_normative_documents_are_paired
    test_process_version_records_contract_change
    test_native_gate_emits_structured_results
    test_configured_acceptance_scripts_are_present
  )
  foreach(TEST_METHOD IN LISTS IROS2J_MIGRATION_TESTS)
    ament_add_test(
      "repository_${TEST_METHOD}"
      COMMAND "${Python3_EXECUTABLE}" -m unittest
        "tests.test_iros2j_migration.Iros2jMigrationTest.${TEST_METHOD}"
      WORKING_DIRECTORY "${REPOSITORY_ROOT}"
      TIMEOUT 60
      GENERATE_RESULT_FOR_RETURN_CODE_ZERO
    )
  endforeach()
  ament_add_test(
    repository_launch_contract
    COMMAND "${Python3_EXECUTABLE}" -m unittest tests.test_launch_contract
    WORKING_DIRECTORY "${REPOSITORY_ROOT}"
    TIMEOUT 60
    GENERATE_RESULT_FOR_RETURN_CODE_ZERO
  )
  ament_add_test(
    repository_dataset_e2e_contract
    COMMAND "${Python3_EXECUTABLE}" -m unittest tests.test_dataset_e2e
    WORKING_DIRECTORY "${REPOSITORY_ROOT}"
    TIMEOUT 60
    GENERATE_RESULT_FOR_RETURN_CODE_ZERO
  )
  ament_add_test(
    repository_amd64_release_contract
    COMMAND "${Python3_EXECUTABLE}" -m unittest
      tests.test_amd64_release_contract
    WORKING_DIRECTORY "${REPOSITORY_ROOT}"
    TIMEOUT 60
    GENERATE_RESULT_FOR_RETURN_CODE_ZERO
  )
endif()


ament_package()
