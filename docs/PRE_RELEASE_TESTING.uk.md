# Передрелізне тестування

Кожна запланована перевірка отримує один явний результат із моделі станів
process governance.

## Обов’язкові gates

| Gate | Умова прийняття |
|---|---|
| Metadata | Product/tag/manifest/changelog узгоджені; підписані assets і незмінні commits зафіксовані. |
| Platform | Native Raspberry Pi 5, Debian 13, `aarch64`/`arm64`; Docker, емуляція й cross-compilation не є evidence. |
| Runtime | Немає `iros2-0` та `/opt/iros2_0`; кожний потрібний `iros2j-*` має точну версію `1.0.3-1+deb13`. |
| Build | Після source `/opt/iros2j/setup.bash` Release build і `colcon test` проходять. |
| Ownership | `ros2 pkg prefix cv_bridge` дорівнює `/opt/iros2j`; `/opt/vins` не містить приватного ROS underlay. |
| Package | ARM64 metadata, точні залежності, portability, checksum і повний ELF linkage проходять. |
| Install | Clean APT install і clean-shell VINS smoke проходять. |
| Integration | `/opt/iros2j`, `/opt/imavros`, `/opt/vins` активуються саме в цьому порядку; Fast DDS, topics, QoS, timestamps і frames проходять. |
| Dataset | Контрольований VINS dataset проходить на налаштованій Raspberry Pi 5. |
| Post-release | Опубліковані checksum, reinstall, smoke та integration checks проходять. |

Тривалий звіт ОБОВ’ЯЗКОВО містить test ID, result, timestamps, host, target,
точну command, commit, dependency identity, evidence path і причину кожного
результату, відмінного від `PASS`.

Для acceptance-перевірок на налаштованій Raspberry Pi 5 виконайте:

```bash
tools/native-dataset-smoke.sh /path/to/ros2_bag /path/to/dataset-evidence
tools/native-hardware-smoke.sh /path/to/hardware-evidence
```

Dataset gate вимагає `/imu0`, `/cam0/image_raw` та отримане повідомлення
`/vins_estimator/odometry`. Hardware gate захоплює реальний кадр OV5647 і
вимагає heartbeat ArduPilot через `/dev/ttyAMA10` на швидкості 460800.
