#include <stdio.h>
#include <queue>
#include <map>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <limits>
#include <rclcpp/rclcpp.hpp>
#include <cv_bridge/cv_bridge.hpp>
#include <opencv2/opencv.hpp>

#include "estimator.h"
#include "parameters.h"
#include "utility/visualization.h"
#include "version.h"


Estimator estimator;
rclcpp::Node::SharedPtr estimator_node;

std::condition_variable con;
double current_time = -1;
queue<sensor_msgs::msg::Imu::SharedPtr> imu_buf;
queue<sensor_msgs::msg::PointCloud::SharedPtr> feature_buf;
queue<sensor_msgs::msg::PointCloud::SharedPtr> relo_buf;
int sum_of_wait = 0;

std::mutex m_buf;
std::mutex m_state;
std::mutex i_buf;
std::mutex m_estimator;

double latest_time;
Eigen::Vector3d tmp_P;
Eigen::Quaterniond tmp_Q;
Eigen::Vector3d tmp_V;
Eigen::Vector3d tmp_Ba;
Eigen::Vector3d tmp_Bg;
Eigen::Vector3d acc_0;
Eigen::Vector3d gyr_0;
bool init_feature = 0;
bool init_imu = 1;
double last_imu_t = 0;
std::atomic<uint64_t> imu_messages_received{0};
std::atomic<uint64_t> feature_messages_received{0};
std::atomic<double> last_imu_stamp_received{0.0};
std::atomic<double> last_feature_stamp_received{0.0};
std::atomic<bool> sensor_processing_started{false};

const char *stateName(Estimator::SolverFlag state)
{
    return state == Estimator::SolverFlag::INITIAL ? "INITIALIZING" : "TRACKING";
}

void logStateTransition(
    Estimator::SolverFlag previous,
    Estimator::SolverFlag current)
{
    if (!estimator_node || previous == current)
        return;

    finishRuntimeStatusLine();
    RCLCPP_INFO(estimator_node->get_logger(), "[STATE END] %s", stateName(previous));
    RCLCPP_INFO(estimator_node->get_logger(), "[STATE BEGIN] %s", stateName(current));

    if (current == Estimator::SolverFlag::NON_LINEAR)
    {
        const Eigen::Vector3d ypr = Utility::R2ypr(estimator.Rs[WINDOW_SIZE]);
        const auto logger = estimator_node->get_logger();
        int valid_depth_features = 0;
        double minimum_depth = std::numeric_limits<double>::infinity();
        double maximum_depth = 0.0;
        double depth_sum = 0.0;
        for (const auto &feature : estimator.f_manager.feature)
        {
            if (feature.estimated_depth > 0.0 && std::isfinite(feature.estimated_depth))
            {
                ++valid_depth_features;
                depth_sum += feature.estimated_depth;
                minimum_depth = std::min(minimum_depth, feature.estimated_depth);
                maximum_depth = std::max(maximum_depth, feature.estimated_depth);
            }
        }
        const double mean_depth =
            valid_depth_features > 0 ? depth_sum / valid_depth_features : 0.0;
        if (valid_depth_features == 0)
            minimum_depth = 0.0;

        const char *extrinsic_source =
            ESTIMATE_EXTRINSIC == 0 ? "CONFIGURED_FIXED" : "ONLINE_ESTIMATED";

        RCLCPP_INFO(logger, "========== INITIALIZATION COMPLETED BEGIN ==========");
        RCLCPP_INFO(logger, "initialization_stage=FINAL_NON_LINEAR");
        RCLCPP_INFO(logger, "window_frames=%d/%d", estimator.frame_count, WINDOW_SIZE);
        RCLCPP_INFO(logger, "tracked_features=%d", estimator.f_manager.last_track_num);
        RCLCPP_INFO(logger, "metric_scale=%.9f", estimator.initialization_metric_scale);
        RCLCPP_INFO(logger, "imu_excitation=%.9f", estimator.initialization_imu_excitation);
        RCLCPP_INFO(logger, "visual_parallax_px=%.6f", estimator.initialization_visual_parallax_px);
        RCLCPP_INFO(logger, "gravity_before_alignment_xyz=[%.6f %.6f %.6f]",
            estimator.initialization_gravity_before_alignment.x(),
            estimator.initialization_gravity_before_alignment.y(),
            estimator.initialization_gravity_before_alignment.z());
        RCLCPP_INFO(logger, "initial_alignment_ypr_deg=[%.6f %.6f %.6f]",
            estimator.initialization_alignment_ypr_deg.x(),
            estimator.initialization_alignment_ypr_deg.y(),
            estimator.initialization_alignment_ypr_deg.z());
        RCLCPP_INFO(logger, "position_xyz=[%.6f %.6f %.6f]",
            estimator.Ps[WINDOW_SIZE].x(), estimator.Ps[WINDOW_SIZE].y(), estimator.Ps[WINDOW_SIZE].z());
        RCLCPP_INFO(logger, "orientation_ypr_deg=[%.6f %.6f %.6f]",
            ypr.x(), ypr.y(), ypr.z());
        RCLCPP_INFO(logger, "velocity_xyz=[%.6f %.6f %.6f]",
            estimator.Vs[WINDOW_SIZE].x(), estimator.Vs[WINDOW_SIZE].y(), estimator.Vs[WINDOW_SIZE].z());
        RCLCPP_INFO(logger, "accelerometer_bias_xyz=[%.6f %.6f %.6f]",
            estimator.Bas[WINDOW_SIZE].x(), estimator.Bas[WINDOW_SIZE].y(), estimator.Bas[WINDOW_SIZE].z());
        RCLCPP_INFO(logger, "gyroscope_bias_xyz=[%.6f %.6f %.6f]",
            estimator.Bgs[WINDOW_SIZE].x(), estimator.Bgs[WINDOW_SIZE].y(), estimator.Bgs[WINDOW_SIZE].z());
        RCLCPP_INFO(logger, "gravity_xyz=[%.6f %.6f %.6f]",
            estimator.g.x(), estimator.g.y(), estimator.g.z());
        RCLCPP_INFO(logger, "time_offset=%.9f", estimator.td);
        RCLCPP_INFO(logger, "time_offset_estimation_mode=%d", ESTIMATE_TD);
        RCLCPP_INFO(logger, "triangulated_features=%d", estimator.f_manager.getFeatureCount());
        RCLCPP_INFO(logger, "valid_depth_features=%d", valid_depth_features);
        RCLCPP_INFO(logger, "feature_depth_mean=%.6f", mean_depth);
        RCLCPP_INFO(logger, "feature_depth_range=[%.6f %.6f]", minimum_depth, maximum_depth);
        RCLCPP_INFO(logger, "camera_count=%d", NUM_OF_CAM);
        RCLCPP_INFO(logger, "extrinsic_estimation_mode=%d", ESTIMATE_EXTRINSIC);
        RCLCPP_INFO(logger, "extrinsic_source=%s", extrinsic_source);

        for (int i = 0; i < NUM_OF_CAM; ++i)
        {
            const Eigen::Vector3d extrinsic_ypr = Utility::R2ypr(estimator.ric[i]);
            RCLCPP_INFO(logger, "camera[%d].extrinsic_translation_xyz=[%.6f %.6f %.6f]",
                i,
                estimator.tic[i].x(), estimator.tic[i].y(), estimator.tic[i].z());
            RCLCPP_INFO(logger, "camera[%d].extrinsic_orientation_ypr_deg=[%.6f %.6f %.6f]",
                i,
                extrinsic_ypr.x(), extrinsic_ypr.y(), extrinsic_ypr.z());
        }
        RCLCPP_INFO(logger, "========== INITIALIZATION COMPLETED END ============");
    }
}

void predict(const sensor_msgs::msg::Imu::SharedPtr imu_msg)
{
    double t = imu_msg->header.stamp.sec+imu_msg->header.stamp.nanosec * (1e-9);
    if (init_imu)
    {
        latest_time = t;
        init_imu = 0;
        return;
    }
    double dt = t - latest_time;
    latest_time = t;

    double dx = imu_msg->linear_acceleration.x;
    double dy = imu_msg->linear_acceleration.y;
    double dz = imu_msg->linear_acceleration.z;
    Eigen::Vector3d linear_acceleration{dx, dy, dz};

    double rx = imu_msg->angular_velocity.x;
    double ry = imu_msg->angular_velocity.y;
    double rz = imu_msg->angular_velocity.z;
    Eigen::Vector3d angular_velocity{rx, ry, rz};

    Eigen::Vector3d un_acc_0 = tmp_Q * (acc_0 - tmp_Ba) - estimator.g;

    Eigen::Vector3d un_gyr = 0.5 * (gyr_0 + angular_velocity) - tmp_Bg;
    tmp_Q = tmp_Q * Utility::deltaQ(un_gyr * dt);

    Eigen::Vector3d un_acc_1 = tmp_Q * (linear_acceleration - tmp_Ba) - estimator.g;

    Eigen::Vector3d un_acc = 0.5 * (un_acc_0 + un_acc_1);

    tmp_P = tmp_P + dt * tmp_V + 0.5 * dt * dt * un_acc;
    tmp_V = tmp_V + dt * un_acc;

    acc_0 = linear_acceleration;
    gyr_0 = angular_velocity;
}

void update()
{
    TicToc t_predict;
    latest_time = current_time;
    tmp_P = estimator.Ps[WINDOW_SIZE];
    tmp_Q = estimator.Rs[WINDOW_SIZE];
    tmp_V = estimator.Vs[WINDOW_SIZE];
    tmp_Ba = estimator.Bas[WINDOW_SIZE];
    tmp_Bg = estimator.Bgs[WINDOW_SIZE];
    acc_0 = estimator.acc_0;
    gyr_0 = estimator.gyr_0;

    queue<sensor_msgs::msg::Imu::SharedPtr> tmp_imu_buf = imu_buf;
    for (sensor_msgs::msg::Imu::SharedPtr tmp_imu_msg; !tmp_imu_buf.empty(); tmp_imu_buf.pop())
        predict(tmp_imu_buf.front());

}

std::vector<std::pair<std::vector<sensor_msgs::msg::Imu::SharedPtr>, sensor_msgs::msg::PointCloud::SharedPtr>>
getMeasurements()
{
    std::vector<std::pair<std::vector<sensor_msgs::msg::Imu::SharedPtr>, sensor_msgs::msg::PointCloud::SharedPtr>> measurements;

    while (true)
    {
        if (imu_buf.empty() || feature_buf.empty())
            return measurements;

        if (!((imu_buf.back()->header.stamp.sec+imu_buf.back()->header.stamp.nanosec * (1e-9)) > (feature_buf.front()->header.stamp.sec+feature_buf.front()->header.stamp.nanosec * (1e-9)) + estimator.td))
        {
            //RCUTILS_LOG_WARN("wait for imu, only should happen at the beginning");
            sum_of_wait++;
            return measurements;
        }

        if (!((imu_buf.front()->header.stamp.sec+imu_buf.front()->header.stamp.nanosec * (1e-9)) < (feature_buf.front()->header.stamp.sec+feature_buf.front()->header.stamp.nanosec * (1e-9)) + estimator.td))
        {
            RCUTILS_LOG_WARN("throw img, only should happen at the beginning");
            feature_buf.pop();
            continue;
        }
        sensor_msgs::msg::PointCloud::SharedPtr img_msg = feature_buf.front();
        feature_buf.pop();

        std::vector<sensor_msgs::msg::Imu::SharedPtr> IMUs;
        while ((imu_buf.front()->header.stamp.sec+imu_buf.front()->header.stamp.nanosec * (1e-9)) < (img_msg->header.stamp.sec+img_msg->header.stamp.nanosec * (1e-9)) + estimator.td)
        {
            IMUs.emplace_back(imu_buf.front());
            imu_buf.pop();
        }
        IMUs.emplace_back(imu_buf.front());
        if (IMUs.empty())
            RCUTILS_LOG_WARN("no imu between two image");
        measurements.emplace_back(IMUs, img_msg);
    }
    return measurements;
}

void imu_callback(const sensor_msgs::msg::Imu::SharedPtr imu_msg)
{
    imu_messages_received.fetch_add(1, std::memory_order_relaxed);
    last_imu_stamp_received.store(
        imu_msg->header.stamp.sec + imu_msg->header.stamp.nanosec * 1e-9,
        std::memory_order_relaxed);
    if ((imu_msg->header.stamp.sec+imu_msg->header.stamp.nanosec * (1e-9)) <= last_imu_t)
    {
        RCUTILS_LOG_WARN("imu message in disorder!");
        return;
    }

    last_imu_t = imu_msg->header.stamp.sec+imu_msg->header.stamp.nanosec * (1e-9);

    m_buf.lock();
    imu_buf.push(imu_msg);
    m_buf.unlock();
    con.notify_one();


    last_imu_t = imu_msg->header.stamp.sec+imu_msg->header.stamp.nanosec * (1e-9);

    {
        std::lock_guard<std::mutex> lg(m_state);
        predict(imu_msg);
        std_msgs::msg::Header header = imu_msg->header;
        header.frame_id = "world";
        if (estimator.solver_flag == Estimator::SolverFlag::NON_LINEAR)
            pubLatestOdometry(tmp_P, tmp_Q, tmp_V, header);
    }
}


void feature_callback(const sensor_msgs::msg::PointCloud::SharedPtr feature_msg)
{
    feature_messages_received.fetch_add(1, std::memory_order_relaxed);
    last_feature_stamp_received.store(
        feature_msg->header.stamp.sec + feature_msg->header.stamp.nanosec * 1e-9,
        std::memory_order_relaxed);
    if (!init_feature)
    {
        //skip the first detected feature, which doesn't contain optical flow speed
        init_feature = 1;
        return;
    }
    m_buf.lock();
    feature_buf.push(feature_msg);
    m_buf.unlock();
    con.notify_one();
}

void restart_callback(const std_msgs::msg::Bool::SharedPtr restart_msg)
{
    if (restart_msg->data == true)
    {
        finishRuntimeStatusLine();
        RCLCPP_WARN(estimator_node->get_logger(), "Estimator restart requested.");
        const Estimator::SolverFlag previous_state = estimator.solver_flag;
        m_buf.lock();
        while(!feature_buf.empty())
            feature_buf.pop();
        while(!imu_buf.empty())
            imu_buf.pop();
        m_buf.unlock();
        m_estimator.lock();
        estimator.clearState();
        estimator.setParameter();
        m_estimator.unlock();
        current_time = -1;
        last_imu_t = 0;
        sensor_processing_started.store(false, std::memory_order_relaxed);
        logStateTransition(previous_state, estimator.solver_flag);
    }
    return;
}

void relocalization_callback(const sensor_msgs::msg::PointCloud::SharedPtr points_msg)
{
    //printf("relocalization callback! \n");
    m_buf.lock();
    relo_buf.push(points_msg);
    m_buf.unlock();
}

// thread: visual-inertial odometry
void process()
{
    while (rclcpp::ok())
    {
        std::vector<std::pair<std::vector<sensor_msgs::msg::Imu::SharedPtr>, sensor_msgs::msg::PointCloud::SharedPtr>> measurements;
        std::unique_lock<std::mutex> lk(m_buf);
        con.wait(lk, [&]
                 {
            return !rclcpp::ok() || (measurements = getMeasurements()).size() != 0;
                 });

        if (!rclcpp::ok())
            break;

        lk.unlock();
        m_estimator.lock();
        for (auto &measurement : measurements)
        {
            sensor_processing_started.store(true, std::memory_order_relaxed);
            auto img_msg = measurement.second;
            double dx = 0, dy = 0, dz = 0, rx = 0, ry = 0, rz = 0;
            for (auto &imu_msg : measurement.first)
            {
                double t = imu_msg->header.stamp.sec+imu_msg->header.stamp.nanosec * (1e-9);
                double img_t = img_msg->header.stamp.sec+img_msg->header.stamp.nanosec * (1e-9) + estimator.td;
                if (t <= img_t)
                { 
                    if (current_time < 0)
                        current_time = t;
                    double dt = t - current_time;
                    assert(dt >= 0);
                    current_time = t;
                    dx = imu_msg->linear_acceleration.x;
                    dy = imu_msg->linear_acceleration.y;
                    dz = imu_msg->linear_acceleration.z;
                    rx = imu_msg->angular_velocity.x;
                    ry = imu_msg->angular_velocity.y;
                    rz = imu_msg->angular_velocity.z;
                    estimator.processIMU(dt, Vector3d(dx, dy, dz), Vector3d(rx, ry, rz));
                    //printf("imu: dt:%f a: %f %f %f w: %f %f %f\n",dt, dx, dy, dz, rx, ry, rz);

                }
                else
                {
                    double dt_1 = img_t - current_time;
                    double dt_2 = t - img_t;
                    current_time = img_t;
                    assert(dt_1 >= 0);
                    assert(dt_2 >= 0);
                    assert(dt_1 + dt_2 > 0);
                    double w1 = dt_2 / (dt_1 + dt_2);
                    double w2 = dt_1 / (dt_1 + dt_2);
                    dx = w1 * dx + w2 * imu_msg->linear_acceleration.x;
                    dy = w1 * dy + w2 * imu_msg->linear_acceleration.y;
                    dz = w1 * dz + w2 * imu_msg->linear_acceleration.z;
                    rx = w1 * rx + w2 * imu_msg->angular_velocity.x;
                    ry = w1 * ry + w2 * imu_msg->angular_velocity.y;
                    rz = w1 * rz + w2 * imu_msg->angular_velocity.z;
                    estimator.processIMU(dt_1, Vector3d(dx, dy, dz), Vector3d(rx, ry, rz));
                    //printf("dimu: dt:%f a: %f %f %f w: %f %f %f\n",dt_1, dx, dy, dz, rx, ry, rz);
                }
            }
            // set relocalization frame
            sensor_msgs::msg::PointCloud::SharedPtr relo_msg = NULL;
            while (!relo_buf.empty())
            {
                relo_msg = relo_buf.front();
                relo_buf.pop();
            }
            if (relo_msg != NULL)
            {
                vector<Vector3d> match_points;
                double frame_stamp = relo_msg->header.stamp.sec+relo_msg->header.stamp.nanosec * (1e-9);
                for (unsigned int i = 0; i < relo_msg->points.size(); i++)
                {
                    Vector3d u_v_id;
                    u_v_id.x() = relo_msg->points[i].x;
                    u_v_id.y() = relo_msg->points[i].y;
                    u_v_id.z() = relo_msg->points[i].z;
                    match_points.push_back(u_v_id);
                }
                Vector3d relo_t(relo_msg->channels[0].values[0], relo_msg->channels[0].values[1], relo_msg->channels[0].values[2]);
                Quaterniond relo_q(relo_msg->channels[0].values[3], relo_msg->channels[0].values[4], relo_msg->channels[0].values[5], relo_msg->channels[0].values[6]);
                Matrix3d relo_r = relo_q.toRotationMatrix();
                int frame_index;
                frame_index = relo_msg->channels[0].values[7];
                estimator.setReloFrame(frame_stamp, frame_index, match_points, relo_t, relo_r);
            }

            RCUTILS_LOG_DEBUG("processing vision data with stamp %f \n", img_msg->header.stamp.sec+img_msg->header.stamp.nanosec * (1e-9));

            TicToc t_s;
            map<int, vector<pair<int, Eigen::Matrix<double, 7, 1>>>> image;
            for (unsigned int i = 0; i < img_msg->points.size(); i++)
            {
                int v = img_msg->channels[0].values[i] + 0.5;
                int feature_id = v / NUM_OF_CAM;
                int camera_id = v % NUM_OF_CAM;
                double x = img_msg->points[i].x;
                double y = img_msg->points[i].y;
                double z = img_msg->points[i].z;
                double p_u = img_msg->channels[1].values[i];
                double p_v = img_msg->channels[2].values[i];
                double velocity_x = img_msg->channels[3].values[i];
                double velocity_y = img_msg->channels[4].values[i];
                assert(z == 1);
                Eigen::Matrix<double, 7, 1> xyz_uv_velocity;
                xyz_uv_velocity << x, y, z, p_u, p_v, velocity_x, velocity_y;
                image[feature_id].emplace_back(camera_id,  xyz_uv_velocity);
            }
            const Estimator::SolverFlag previous_state = estimator.solver_flag;
            estimator.processImage(image, img_msg->header);
            logStateTransition(previous_state, estimator.solver_flag);

            double whole_t = t_s.toc();
            logStatistics(
                estimator, whole_t,
                estimator_node->get_logger(), LOG_PERIOD_MS);
            std_msgs::msg::Header header = img_msg->header;
            header.frame_id = "world";

            pubOdometry(estimator, header);
            pubKeyPoses(estimator, header);
            pubCameraPose(estimator, header);
            pubPointCloud(estimator, header);
            pubTF(estimator, header);
            pubKeyframe(estimator);
            if (relo_msg != NULL)
                pubRelocalization(estimator);
            //RCUTILS_LOG_ERROR("end: %f, at %f", img_msg->header.stamp.toSec(), ros::Time::now().toSec());
        }
        m_estimator.unlock();
        m_buf.lock();
        m_state.lock();
        if (estimator.solver_flag == Estimator::SolverFlag::NON_LINEAR)
            update();
        m_state.unlock();
        m_buf.unlock();
    }
}

int main(int argc, char **argv)
{
    if (argc == 2 &&
        (std::string(argv[1]) == "--version" || std::string(argv[1]) == "-V"))
    {
        std::cout << "VINS-MONO ROS 2 " << VINS_MONO_VERSION
                  << " (" << VINS_MONO_RELEASE_TAG << ")" << std::endl;
        return 0;
    }

    std::cout << "VINS-MONO ROS 2 " << VINS_MONO_VERSION
              << " (" << VINS_MONO_RELEASE_TAG << ")" << std::endl;
    rclcpp::init(argc, argv);
    auto n = rclcpp::Node::make_shared("vins_estimator");
    estimator_node = n;
    if (!configureLogging(n))
    {
        rclcpp::shutdown();
        return 1;
    }
    RCLCPP_INFO(n->get_logger(), "VINS-MONO ROS 2 version=%s release=%s",
                VINS_MONO_VERSION, VINS_MONO_RELEASE_TAG);
    RCLCPP_INFO(n->get_logger(), "Logging configured: level=%s, period_ms=%d",
                LOG_LEVEL.c_str(), LOG_PERIOD_MS);
    readParameters(n);
    estimator.setParameter();
#ifdef EIGEN_DONT_PARALLELIZE
    RCUTILS_LOG_DEBUG("EIGEN_DONT_PARALLELIZE");
#endif
    RCLCPP_INFO(n->get_logger(), "[STATE BEGIN] INITIALIZING");
    auto waiting_status_timer = n->create_wall_timer(
        std::chrono::milliseconds(std::max(1, LOG_PERIOD_MS)),
        [n]()
        {
            if (sensor_processing_started.load(std::memory_order_relaxed))
                return;
            logWaitingStatus(
                n->get_logger(),
                imu_messages_received.load(std::memory_order_relaxed),
                feature_messages_received.load(std::memory_order_relaxed),
                LOG_PERIOD_MS);
        });

    registerPub(n);

    auto sub_imu = n->create_subscription<sensor_msgs::msg::Imu>(IMU_TOPIC, rclcpp::QoS(rclcpp::KeepLast(2000)), imu_callback);
    auto sub_image = n->create_subscription<sensor_msgs::msg::PointCloud>("/feature_tracker/feature", rclcpp::QoS(rclcpp::KeepLast(2000)), feature_callback);
    auto sub_restart = n->create_subscription<std_msgs::msg::Bool>("/feature_tracker/restart", rclcpp::QoS(rclcpp::KeepLast(2000)), restart_callback);
    auto sub_relo_points = n->create_subscription<sensor_msgs::msg::PointCloud>("/pose_graph/match_points", rclcpp::QoS(rclcpp::KeepLast(2000)), relocalization_callback);

    logWaitingStatus(
        n->get_logger(),
        imu_messages_received.load(std::memory_order_relaxed),
        feature_messages_received.load(std::memory_order_relaxed),
        0);

    std::thread measurement_process{process};
    rclcpp::spin(n);
    con.notify_all();
    measurement_process.join();
    sub_relo_points.reset();
    sub_restart.reset();
    sub_image.reset();
    sub_imu.reset();
    waiting_status_timer.reset();
    unregisterPub();
    estimator_node.reset();
    n.reset();

    return 0;
}
