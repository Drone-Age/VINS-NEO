# VINS-MONO-ROS2: посібник користувача

Цей документ описує підготовку, збирання, запуск і первинну діагностику
VINS-MONO-ROS2. Окремий детальний опис журналювання наведено в
[LOGGING_UK.md](LOGGING_UK.md).

## 1. Призначення

VINS-Mono — система візуально-інерціальної одометрії для однієї камери та
IMU. Оцінювач використовує оптимізацію у ковзному вікні, IMU
pre-integration, автоматичну ініціалізацію, виявлення відмов і відновлення.
Початковий проєкт також передбачає калібрування extrinsic-параметрів,
оцінювання часової різниці камери та IMU, loop closure і pose graph.

Цей ROS 2 порт складається з пакетів:

- `camera_model` — моделі та калібрування камер;
- `feature_tracker` — пошук і супровід візуальних ознак;
- `vins_estimator` — ініціалізація та нелінійна VIO-оптимізація;
- `pose_graph` — loop closure і глобальна оптимізація траєкторії;
- `config_pkg` — YAML-конфігурації та допоміжні файли;
- `benchmark_publisher` — публікація еталонної траєкторії;
- `ar_demo` — демонстраційний AR-сценарій.

## 2. Версія

Версія продукту має формат `MAJOR.MINOR.FEATURE.PATCH`, наприклад
`1.0.2.0`. Git-тег для цієї версії — `v1_00_02_00`.

Перевірити версію встановленого executable:

```bash
ros2 run vins_estimator vins_estimator --version
```

Очікуваний результат:

```text
VINS-MONO ROS 2 1.0.2.0 (v1_00_02_00)
```

ROS `package.xml` використовує стандартну трикомпонентну версію `1.0.2`,
тому четвертий компонент зберігається на рівні продукту, Git-тегу та
executable.

## 3. Системні вимоги

Поточна гілка проєкту адаптована для Ubuntu 24.04 і ROS 2 Jazzy. Основні
залежності:

- ROS 2 та `colcon`;
- OpenCV 4;
- Eigen 3;
- Ceres Solver;
- Boost;
- стандартні ROS 2 пакети повідомлень, TF2, `cv_bridge` та
  `image_transport`.

Версії залежностей у конкретному середовищі можна перевірити командами:

```bash
ros2 doctor --report
cmake --version
pkg-config --modversion opencv4
```

## 4. Збирання

```bash
cd ~/vins_ws
source /opt/iros2_0/jazzy/setup.bash
colcon build --symlink-install --executor sequential
source install/setup.bash
```

Для Raspberry Pi рекомендована послідовна збірка. Вона триває довше, але
зменшує пікове використання RAM і навантаження на систему.

Після зміни лише estimator:

```bash
cd ~/vins_ws
source /opt/iros2_0/jazzy/setup.bash
colcon build \
  --symlink-install \
  --executor sequential \
  --packages-select vins_estimator
source install/setup.bash
```

Якщо ROS 2 встановлено в іншому каталозі, використовуйте фактичний шлях до
його `setup.bash`.

## 5. Конфігурація сенсорів

Приклад конфігурації EuRoC:

```text
config_pkg/config/euroc/euroc_config.yaml
```

Ключові групи параметрів:

| Група | Параметри | Призначення |
|---|---|---|
| Topics | `imu_topic`, `image_topic` | Вхідні IMU та зображення |
| Камера | `model_type`, розмір, distortion, projection | Intrinsic-калібрування |
| Extrinsic | `estimate_extrinsic`, `extrinsicRotation`, `extrinsicTranslation` | Перетворення камера–IMU |
| Tracker | `max_cnt`, `min_dist`, `freq`, `F_threshold` | Супровід ознак |
| Solver | `max_solver_time`, `max_num_iterations`, `keyframe_parallax` | Обмеження оптимізатора |
| IMU | `acc_n`, `acc_w`, `gyr_n`, `gyr_w`, `g_norm` | Модель шумів IMU |
| Time offset | `estimate_td`, `td` | Часова різниця камера–IMU |
| Rolling shutter | `rolling_shutter`, `rolling_shutter_tr` | Модель зчитування кадру |

Перед роботою з власними сенсорами потрібно отримати:

1. Intrinsic-параметри камери й distortion.
2. Extrinsic rotation/translation між камерою та IMU.
3. Густини шуму та random walk IMU.
4. Узгоджені часові штампи камери й IMU.
5. Правильні ROS topics і frame conventions.

Неточні extrinsic-параметри, неправильний масштаб часу або невірна модель
шумів можуть призвести до нестабільної ініціалізації та дрейфу.

## 6. Запуск

У різних терміналах:

```bash
source ~/vins_ws/install/setup.bash
ros2 launch feature_tracker vins_feature_tracker.launch.py
```

```bash
source ~/vins_ws/install/setup.bash
ros2 launch vins_estimator euroc.launch.py
```

Для EuRoC bag:

```bash
cd ~/bag
ros2 bag play data
```

Перевірити надходження даних:

```bash
ros2 topic hz /imu0
ros2 topic hz /feature_tracker/feature
```

Назва IMU topic визначається параметром `imu_topic` у YAML. Список
фактичних topics:

```bash
ros2 topic list
```

## 7. Стани estimator

Estimator показує поточний стан через ROS INFO:

### `WAITING`

Estimator очікує IMU або результати feature tracker:

```text
state=WAITING imu_status=MISSING imu_messages=0 camera_status=MISSING camera_feature_messages=0
```

`camera_status` стосується повідомлень `/feature_tracker/feature`, а не
безпосередньо raw image.

### `INITIALIZING`

Заповнюється ковзне вікно та перевіряється достатність руху:

```text
state=INITIALIZING frames=10/10 feat=240 ms=0.3 imu=LOW_EXCITATION vision=LOW_MOTION
```

Для успішної ініціалізації потрібні:

- зміни прискорення та орієнтації для спостережуваності IMU;
- достатній паралакс візуальних ознак;
- синхронні camera/IMU дані;
- стабільний feature tracking.

Пристрій варто рухати плавно в кількох напрямках із помірними поворотами.

### `TRACKING`

Після успішної ініціалізації:

```text
state=TRACKING pos=[5.69 3.04 1.19] ypr=[8.94 32.20 165.92] vel=[7.35 4.21 -0.81] feat=141 td=0.0016 ms=16.0
```

Поля:

- `pos` — позиція XYZ у світовій системі координат;
- `ypr` — yaw, pitch, roll у градусах;
- `vel` — швидкість XYZ;
- `feat` — кількість ознак поточного кадру;
- `td` — оцінена/задана часова різниця камера–IMU;
- `ms` — час обробки кадру в мілісекундах.

Час події вже міститься у стандартному ROS-префіксі. Окремий sensor
`stamp` у коротких статусах не виводиться.

## 8. Звіт успішної ініціалізації

При переході до TRACKING estimator друкує багаторядковий блок:

```text
========== INITIALIZATION COMPLETED BEGIN ==========
initialization_stage=FINAL_NON_LINEAR
window_frames=10/10
tracked_features=...
metric_scale=...
imu_excitation=...
visual_parallax_px=...
gravity_before_alignment_xyz=[...]
initial_alignment_ypr_deg=[...]
position_xyz=[...]
orientation_ypr_deg=[...]
velocity_xyz=[...]
accelerometer_bias_xyz=[...]
gyroscope_bias_xyz=[...]
gravity_xyz=[...]
time_offset=...
time_offset_estimation_mode=...
triangulated_features=...
valid_depth_features=...
feature_depth_mean=...
feature_depth_range=[... ...]
camera_count=...
extrinsic_estimation_mode=...
extrinsic_source=...
camera[0].extrinsic_translation_xyz=[...]
camera[0].extrinsic_orientation_ypr_deg=[...]
========== INITIALIZATION COMPLETED END ============
```

Це компактний фінальний знімок результату ініціалізації після першої
нелінійної оптимізації. Він містить параметри руху та агреговану статистику
глибин без переліку окремих landmarks або feature tracks. Для кожної камери
виводяться окремі extrinsic-параметри.

## 9. Типові проблеми

### Немає IMU

Ознака:

```text
imu_status=MISSING
```

Перевірити:

```bash
ros2 topic list
ros2 topic hz /imu0
ros2 topic echo /imu0 --once
```

Також перевірте `imu_topic` у YAML і QoS джерела.

### Немає camera features

Ознака:

```text
camera_status=MISSING
```

Перевірити raw image та tracker:

```bash
ros2 topic hz /cam0/image_raw
ros2 topic hz /feature_tracker/feature
ros2 node list
```

### `LOW_EXCITATION`

IMU не отримала достатньо різноманітного руху. Виконайте плавні
поступальні рухи та повороти навколо кількох осей.

### `LOW_MOTION`

Недостатній паралакс або ознаки нестабільні. Перевірте:

- освітлення й різкість зображення;
- частоту та exposure камери;
- `max_cnt`, `min_dist`, `F_threshold`;
- напрям і амплітуду руху;
- intrinsic/extrinsic-калібрування.

### Великий або нестабільний `ms`

Перевірте навантаження CPU, температуру, throttling, частоту кадрів і
параметри solver. На Raspberry:

```bash
uptime
top
vcgencmd measure_temp
vcgencmd get_throttled
```

## 10. Англомовні матеріали

- [Оригінальний VINS-Mono та пов’язані публікації](https://github.com/HKUST-Aerial-Robotics/VINS-Mono)
- [EuRoC MAV Dataset](https://projects.asl.ethz.ch/datasets/doku.php?id=kmavvisualinertialdatasets)
- [ROS 2 Jazzy: Logging](https://docs.ros.org/en/jazzy/Concepts/Intermediate/About-Logging.html)
- [ROS 2 Jazzy: logging examples and configuration](https://docs.ros.org/en/jazzy/Tutorials/Demos/Logging-and-logger-configuration.html)
- [ROS 2 Jazzy documentation](https://docs.ros.org/en/jazzy/)
- [Ceres Solver documentation](https://ceres-solver.readthedocs.io/)
- [Eigen documentation](https://eigen.tuxfamily.org/dox/)
- [OpenCV camera calibration](https://docs.opencv.org/4.x/dc/dbb/tutorial_py_calibration.html)

