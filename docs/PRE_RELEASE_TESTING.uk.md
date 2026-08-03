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
| Dataset | Підготовлений незмінний DSM run-manifest проходить VINS-owned runner на налаштованій Raspberry Pi 5. |
| Post-release | Опубліковані checksum, reinstall, smoke та integration checks проходять. |

Тривалий звіт ОБОВ’ЯЗКОВО містить test ID, result, timestamps, host, target,
точну command, commit, dependency identity, evidence path і причину кожного
результату, відмінного від `PASS`.

Для acceptance-перевірки на налаштованій Raspberry Pi 5 підготуйте dataset на
host через HTTPS, укажіть `DATASET_RUN_MANIFEST` в ignored native environment і
виконайте:

```powershell
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

Dataset gate вимагає ненульові `/imu0` і `/cam0/image_raw`, роботу обох
VINS-процесів до завершення bag і щонайменше 10 повідомлень
`/vins_estimator/odometry` зі скінченними значеннями та монотонними timestamps.
Результат фіксує всі dataset, profile, artifact, configuration, suite та Client
version inputs. Evidence з Ubuntu AMD64 є лише development evidence; release
evidence потребує native запуску на Debian 13 ARM64.

Окремий hardware gate запускається як `tools/native-hardware-smoke.sh
/path/to/hardware-evidence`. Він захоплює реальний кадр OV5647 і вимагає
heartbeat ArduPilot через `/dev/ttyAMA10` на швидкості 460800.
