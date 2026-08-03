"""Launch feature_tracker and vins_estimator with one shared configuration."""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, LogInfo
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue
from ament_index_python.packages import get_package_share_directory


def generate_launch_description():
    config_package = get_package_share_directory('config_pkg')
    default_config = PathJoinSubstitution([
        config_package,
        'config/euroc/euroc_config.yaml',
    ])
    default_vins_folder = PathJoinSubstitution([config_package, ''])

    config_file = LaunchConfiguration('config_file')
    vins_folder = LaunchConfiguration('vins_folder')
    use_sim_time = LaunchConfiguration('use_sim_time')
    log_level = LaunchConfiguration('log_level')
    logging_period_ms = LaunchConfiguration('logging_period_ms')

    common_parameters = {
        'config_file': config_file,
        'vins_folder': vins_folder,
        'use_sim_time': ParameterValue(use_sim_time, value_type=bool),
    }
    feature_tracker = Node(
        package='feature_tracker',
        executable='feature_tracker',
        name='feature_tracker',
        namespace='feature_tracker',
        output='screen',
        arguments=['--ros-args', '--log-level', log_level],
        parameters=[common_parameters],
    )
    estimator = Node(
        package='vins_estimator',
        executable='vins_estimator',
        name='vins_estimator',
        namespace='vins_estimator',
        output='screen',
        emulate_tty=True,
        arguments=['--ros-args', '--log-level', log_level],
        additional_env={
            'RCUTILS_COLORIZED_OUTPUT': '1',
            'GLOG_minloglevel': '1',
            'GLOG_v': '-1',
            'GLOG_vmodule': '*=-1',
        },
        parameters=[{
            **common_parameters,
            'logging.level': log_level,
            'logging.period_ms': ParameterValue(logging_period_ms, value_type=int),
        }],
    )

    return LaunchDescription([
        DeclareLaunchArgument(
            'config_file', default_value=default_config,
            description='YAML configuration shared by both VINS nodes',
        ),
        DeclareLaunchArgument(
            'vins_folder', default_value=default_vins_folder,
            description='VINS root for optional masks and support files',
        ),
        DeclareLaunchArgument('use_sim_time', default_value='false'),
        DeclareLaunchArgument('log_level', default_value='info'),
        DeclareLaunchArgument('logging_period_ms', default_value='2000'),
        LogInfo(msg=['[vins-neo launch] shared config: ', config_file]),
        feature_tracker,
        estimator,
    ])
