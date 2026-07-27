cmake_minimum_required(VERSION 3.5)
project(camera_model)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-Wextra -Wpedantic)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)

find_package(Boost REQUIRED)
include_directories(${Boost_INCLUDE_DIRS})
find_library(BOOST_FILESYSTEM_LIBRARY NAMES boost_filesystem)
find_library(BOOST_PROGRAM_OPTIONS_LIBRARY NAMES boost_program_options)

find_package(OpenCV 4 REQUIRED)
find_package(Ceres REQUIRED)
include_directories(${CERES_INCLUDE_DIRS})

ament_export_include_directories(include)
ament_export_libraries(camera_model)
ament_export_dependencies(std_msgs)

include_directories("include")

add_library(camera_model
    src/chessboard/Chessboard.cc
    src/calib/CameraCalibration.cc
    src/camera_models/Camera.cc
    src/camera_models/CameraFactory.cc
    src/camera_models/CostFunctionFactory.cc
    src/camera_models/PinholeCamera.cc
    src/camera_models/CataCamera.cc
    src/camera_models/EquidistantCamera.cc
    src/camera_models/ScaramuzzaCamera.cc
    src/sparse_graph/Transform.cc
    src/gpl/gpl.cc
    src/gpl/EigenQuaternionParameterization.cc)

target_link_libraries(camera_model ${OpenCV_LIBS} ${CERES_LIBRARIES})

if(BOOST_FILESYSTEM_LIBRARY AND BOOST_PROGRAM_OPTIONS_LIBRARY)
    add_executable(Calibration
        src/intrinsic_calib.cc
        src/chessboard/Chessboard.cc
        src/calib/CameraCalibration.cc
        src/camera_models/Camera.cc
        src/camera_models/CameraFactory.cc
        src/camera_models/CostFunctionFactory.cc
        src/camera_models/PinholeCamera.cc
        src/camera_models/CataCamera.cc
        src/camera_models/EquidistantCamera.cc
        src/camera_models/ScaramuzzaCamera.cc
        src/sparse_graph/Transform.cc
        src/gpl/gpl.cc
        src/gpl/EigenQuaternionParameterization.cc)
    target_link_libraries(Calibration
        ${BOOST_FILESYSTEM_LIBRARY}
        ${BOOST_PROGRAM_OPTIONS_LIBRARY}
        ${OpenCV_LIBS}
        ${CERES_LIBRARIES})
    install(TARGETS Calibration
        RUNTIME DESTINATION lib/${PROJECT_NAME})
else()
    message(STATUS
        "Boost filesystem/program_options libraries are unavailable; "
        "the optional offline Calibration utility will not be built")
endif()

install(TARGETS camera_model
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)
  
install(DIRECTORY include/
    DESTINATION include/
)

ament_package()
