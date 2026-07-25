# Ручна перевірка опублікованого пакета

Цей режим не запускає VINS або rosbag автоматично. Усі операції виконуються
користувачем окремо, а конфігурація доступна на Windows у
`runtime-config\iVIN.yaml`.

## 1. Підготовка

У PowerShell з кореня репозиторію:

```powershell
$env:VINS_DATA_DIR = 'D:\FILES\Kkovalenko\OneDrive\Projects\VINS\Документы проекта\Компоненты\VINS\VINS-NEO-V1\dataset\iVIN_v0\1'
docker compose -f compose.runtime.yaml --profile manual up -d --no-build manual
docker compose -f compose.runtime.yaml --profile manual ps
```

Якщо готового runtime-образу ще немає, один раз виконайте
`docker compose -f compose.runtime.yaml build manual`. Після цього перевірки
виконуються з `--no-build`.

Скопіюйте початковий конфіг із пакета:

```powershell
docker compose -f compose.runtime.yaml --profile manual cp `
  manual:/opt/vins/share/config_pkg/config/euroc/euroc_config.yaml `
  .\runtime-config\iVIN.yaml
Get-Content .\runtime-config\iVIN.yaml
```

EuRoC-конфіг не є калібруванням iVIN. Перед оцінкою траєкторії перевірте
розмір кадру, intrinsics, distortion, перетворення камера–IMU та параметри
шуму IMU.

## 2. Поточні налаштування

Повний активний YAML:

```powershell
Get-Content .\runtime-config\iVIN.yaml
```

Версія встановленого пакета і шлях до штатного конфіга:

```powershell
docker compose -f compose.runtime.yaml exec manual dpkg-query -W vins-mono-ros2
docker compose -f compose.runtime.yaml exec manual dpkg-query -W iros2-0
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 pkg prefix --share config_pkg
```

Після запуску вузлів можна перевірити параметр, який вказує на YAML:

```powershell
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 param get /feature_tracker/feature_tracker config_file
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 param get /vins_estimator/vins_estimator config_file
```

`ros2 param dump` не показує всі поля VINS: вузли читають більшість значень
безпосередньо з OpenCV YAML. Джерелом істини є `iVIN.yaml`.

## 3. Ручний запуск

Відкрийте чотири PowerShell-термінали.

Термінал 1 — feature tracker:

```powershell
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint bash -lc 'S=$(ros2 pkg prefix --share config_pkg); exec ros2 run feature_tracker feature_tracker --ros-args -r __node:=feature_tracker -r __ns:=/feature_tracker -p config_file:=/config/iVIN.yaml -p vins_folder:=$S'
```

Термінал 2 — estimator:

```powershell
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint bash -lc 'S=$(ros2 pkg prefix --share config_pkg); exec ros2 run vins_estimator vins_estimator --ros-args -r __node:=vins_estimator -r __ns:=/vins_estimator -p config_file:=/config/iVIN.yaml -p vins_folder:=$S -p logging.level:=INFO -p logging.period_ms:=2000'
```

Термінал 3 — bag, спочатку на паузі:

```powershell
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 bag play /data/data --start-paused
```

Натисніть пробіл у цьому терміналі, щоб почати або призупинити відтворення.
Для діагностики ініціалізації можна замість цього додати `--rate 0.5`.

Термінал 4 — контроль:

```powershell
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 node list
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 topic list
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 topic hz /cam0/image_raw
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 topic hz /imu0
```

Команди `topic hz` працюють постійно; зупиняйте їх через `Ctrl+C`.

## 4. Інтерпретація поточного логу

`frames=10/10` означає, що вікно кадрів заповнене. `LOW_EXCITATION` означає
недостатню зміну прискорення для IMU-ініціалізації, а `LOW_MOTION` —
недостатній візуальний паралакс. Падіння `feat` із приблизно 240 до 0–18
свідчить про нестабільне супроводження ознак.

Спочатку звірте `image_width` і `image_height` із реальним повідомленням:

```powershell
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 topic echo /cam0/image_raw --once --timeout 10 --field width
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 topic echo /cam0/image_raw --once --timeout 10 --field height
docker compose -f compose.runtime.yaml exec manual vins-runtime-entrypoint ros2 topic echo /cam0/image_raw --once --timeout 10 --field encoding
```

Ці команди виконуйте, коли bag відтворюється. Якщо розміри збігаються, далі
потрібне реальне калібрування сенсора iVIN. Надійно відновити intrinsics,
distortion і camera–IMU extrinsics лише з `Image` та `Imu` у цьому bag
неможливо.

## 5. Завершення

Зупиніть довгі команди через `Ctrl+C`, потім:

```powershell
docker compose -f compose.runtime.yaml --profile manual down
```
