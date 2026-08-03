from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, LogInfo
from ament_index_python.packages import get_package_share_directory
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node

def generate_launch_description():

    config_pkg_path = get_package_share_directory('config_pkg')

    config_path = PathJoinSubstitution([
        config_pkg_path,
        'config/euroc/euroc_config.yaml'
    ])
    config_file = LaunchConfiguration('config_file')

    vins_path = PathJoinSubstitution([
        config_pkg_path,
        'config/../'
    ])

    support_path = PathJoinSubstitution([
        config_pkg_path,
        'support_files'
    ])

    
    # Define the vins_estimator node
    vins_estimator_node = Node(
        package='vins_estimator',
        executable='vins_estimator',
        name='vins_estimator',
        namespace='vins_estimator',
        output='screen',
        emulate_tty=True,
        additional_env={
            'RCUTILS_COLORIZED_OUTPUT': '1',
            'GLOG_minloglevel': '1',
            # Ceres emits some internal diagnostics at VLOG(0), so zero is
            # still noisy. A negative verbosity disables all VLOG output.
            'GLOG_v': '-1',
            'GLOG_vmodule': '*=-1'
        },
        parameters=[{
            'config_file': config_file,
            'vins_folder': vins_path,
            'logging.level': 'INFO',
            'logging.period_ms': 2000
        }]
    )

    # Define the pose_graph node
    #pose_graph_node = Node(
    #    package='pose_graph',
    #    executable='pose_graph',
    #    name='pose_graph',
    #    namespace='pose_graph',
    #    output='screen',
    #    parameters=[{
    #        'config_file': config_path,
    #        'support_file': support_path,
    #        'visualization_shift_x': 0,
    #        'visualization_shift_y': 0,
    #        'skip_cnt': 0,
    #        'skip_dis': 0.0
    #    }]
    #)

    return LaunchDescription([
        DeclareLaunchArgument(
            'config_file',
            default_value=config_path,
            description='VINS YAML configuration (EuRoC remains the default)'
        ),
        LogInfo(msg=['[vins estimator launch] config path: ', config_file]),
        LogInfo(msg=['[vins estimator launch] vins path: ', vins_path]),
        LogInfo(msg=['[vins estimator launch] support path: ', support_path]),
        vins_estimator_node#,
        #pose_graph_node
    ])
