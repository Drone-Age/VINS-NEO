# Docker: розгортання та робота з VINS-MONO-ROS2

Цей документ описує відтворюване середовище ROS 2 Jazzy для Windows 11,
Linux та Raspberry Pi ARM64.

> **Регламент релізу:** Docker використовується лише для розробки,
> діагностики та додаткових перевірок. Збірка офіційного релізного `.deb` і
> повний передрелізний test gate виконуються виключно на нативній цільовій
> ARM64-системі. Docker-артефакт заборонено публікувати як офіційний реліз.

## 1. Структура

- `Dockerfile`:
  - `dependencies` — ROS 2 Jazzy і системні бібліотеки;
  - `development` — інтерактивне середовище без компіляції VINS;
  - `build` — повна збірка workspace через `colcon`.
- `compose.yaml` — основна Compose-конфігурація.
- `compose.arm64.yaml` — ARM64 development-конфігурація.
- `docker/entrypoint.sh` — команди `build`, `test`, `version`, `shell`.

Перевірене ARM64-середовище:

| Компонент | Версія |
|---|---|
| Ubuntu | 24.04 |
| ROS 2 | Jazzy |
| OpenCV | 4.6.0 |
| Ceres Solver | 2.2.0 |
| Eigen | 3.4.0 |
| Архітектура | `linux/arm64` (`aarch64`) |

## 2. Windows 11

Встановіть Docker Desktop, увімкніть WSL 2 backend і дочекайтеся готовності
Docker Engine. Відкрийте PowerShell у корені репозиторію.

```powershell
docker version
docker compose version
docker buildx ls
```

У списку Buildx platforms має бути `linux/arm64`.

## 3. Створення ARM64 development-образу

Ця команда встановлює ROS і бібліотеки, але не компілює VINS:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml build
```

Перший ARM64 build на x86-64 Windows працює через емуляцію та може тривати
довго. Наступні запуски використовують Docker cache.

Перевірка:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins uname -m
```

Очікується:

```text
aarch64
```

## 4. Інтерактивний shell

Тимчасовий контейнер:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins shell
```

Корисні команди всередині:

```bash
uname -m
echo "$ROS_DISTRO"
cd /workspace
ros2 doctor --report
ros2 node list
ros2 topic list
```

Для виходу виконайте `exit` або натисніть `Ctrl+D`. Вихідний код `/workspace`
змонтований із поточного каталогу хоста, тому зміни файлів зберігаються.

## 5. Постійний контейнер

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml up -d vins
docker compose -f compose.yaml -f compose.arm64.yaml exec vins bash
```

Стан і журнали:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml ps
docker compose -f compose.yaml -f compose.arm64.yaml logs vins
```

Зупинка:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml down
```

## 6. ROS 2 smoke-test

Відкрийте два вікна PowerShell. У першому:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins `
  ros2 topic echo /docker_test std_msgs/msg/String
```

У другому:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins `
  ros2 topic pub --once /docker_test std_msgs/msg/String `
  "{data: 'ARM64 ROS2 works'}"
```

У першому вікні має з’явитися:

```text
data: ARM64 ROS2 works
---
```

Це перевіряє ROS 2 CLI, тип повідомлення, DDS discovery та обмін між
контейнерами.

## 7. Перевірка бібліотек

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins `
  cmake -S /workspace/docker/compatibility `
        -B /tmp/vins-arm64-dependency-check
```

CMake повинен знайти OpenCV, Ceres, Eigen, SuiteSparse, glog і gflags.
Відсутність необов’язкового METIS не блокує Ceres.

## 8. Збірка і тести VINS

Ручна інкрементальна ARM64-збірка:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins build
```

Або всередині shell:

```bash
cd /workspace
colcon build --merge-install --executor sequential
source install/setup.bash
```

Для Raspberry Pi рекомендовано `--executor sequential`, щоб зменшити пікове
використання RAM.

Тести:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins test
```

Перевірка версії після успішної збірки:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins version
```

## 9. Volumes і datasets

Compose зберігає результати між контейнерами:

- `vins-build` — CMake/colcon build;
- `vins-install` — встановлений workspace;
- `vins-log` — журнали colcon.

Dataset монтується read-only у `/data`:

```powershell
$env:VINS_DATA_DIR = "D:\datasets\EuRoC"
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins shell
```

У контейнері:

```bash
ls /data
ros2 bag play /data/MH_01_easy
```

Без `VINS_DATA_DIR` використовується каталог `./data`.

## 10. Перенесення на Raspberry Pi

На Windows:

```powershell
docker save vins-mono-ros2:jazzy-arm64-dev `
  -o vins-mono-ros2-jazzy-arm64-dev.tar
```

Передайте TAR-файл на Raspberry, потім:

```bash
docker load -i vins-mono-ros2-jazzy-arm64-dev.tar
docker image inspect vins-mono-ros2:jazzy-arm64-dev \
  --format '{{.Os}}/{{.Architecture}}'
docker run --rm vins-mono-ros2:jazzy-arm64-dev uname -m
```

Очікується `linux/arm64` і `aarch64`. Контейнер містить Ubuntu 24.04 userspace.
Debian на Raspberry надає kernel і Docker runtime; бібліотеки хоста не
змішуються з бібліотеками контейнера.

## 11. Камера та IMU

На Raspberry пристрої передаються явно:

```bash
docker run --rm -it \
  --device=/dev/video0 \
  --device=/dev/ttyUSB0 \
  vins-mono-ros2:jazzy-arm64-dev
```

Перевірте фактичні пристрої:

```bash
ls -l /dev/video*
ls -l /dev/ttyUSB* /dev/ttyACM*
```

Не використовуйте `--privileged`, якщо достатньо конкретних `--device`.

## 12. Типові проблеми

### Docker API недоступний

Запустіть Docker Desktop і дочекайтеся стану `Engine running`.

### ARM64 build повільний

На x86-64 Windows ARM64-команди виконуються через емуляцію. Не очищайте Docker
cache між звичайними збірками. Для регулярних production-збірок краще
використовувати Raspberry Pi або ARM64 build-agent.

### Контейнери не бачать ROS topics

Перевірте однаковий domain:

```powershell
$env:ROS_DOMAIN_ID = "0"
```

Контейнери також повинні належати одному Compose project/network.

### Графічний інтерфейс на Windows 11: RViz2

RViz2 у Docker є Linux-графічною програмою. Щоб показати її вікно на
Windows 11, потрібен X server для Windows, наприклад VcXsrv. Програма
`XLaunch` входить до складу VcXsrv і запускає та налаштовує X server.

У `XLaunch` виберіть:

1. `Multiple windows`.
2. `Display number: 0` — не використовуйте автоматичне значення `-1`.
3. `Start no client`.
4. `Disable access control` для локального тестування.
5. За проблем з OpenGL також увімкніть `Disable native OpenGL`.

Дозвольте VcXsrv у Windows Firewall для приватної мережі. Режим
`Disable access control` послаблює захист X server, тому не використовуйте
його в недовіреній або публічній мережі.

Перевірте у PowerShell, що display `0` слухає TCP-порт `6000`:

```powershell
Get-NetTCPConnection -LocalPort 6000 -State Listen
```

Перед створенням контейнера задайте `DISPLAY`:

```powershell
$env:DISPLAY = "host.docker.internal:0"
docker compose -f compose.yaml -f compose.arm64.yaml run --rm vins shell
```

У контейнері перевірте змінну та доступність X server:

```bash
echo "$DISPLAY"
timeout 3 bash -c '</dev/tcp/host.docker.internal/6000' \
  && echo "X server доступний" \
  || echo "X server недоступний"
```

Окремий запуск лише RViz2 з готовою VINS-конфігурацією:

```bash
export LIBGL_ALWAYS_SOFTWARE=1
ros2 launch feature_tracker vins_rviz.launch.py
```

Feature tracker і estimator запускайте в інших Docker shell:

```bash
ros2 launch feature_tracker vins_feature_tracker.launch.py
```

```bash
ros2 launch vins_estimator euroc.launch.py
```

Альтернативний launch одночасно запускає feature tracker і RViz2:

```bash
ros2 launch feature_tracker vins_feature_tracker_rviz.launch.py
```

Якщо Qt повідомляє `could not connect to display`, перевірте, що:

- VcXsrv запущений через `XLaunch`;
- вибрано `Display number: 0`;
- Windows Firewall не блокує VcXsrv;
- контейнер створено після встановлення `$env:DISPLAY`;
- `echo "$DISPLAY"` у контейнері повертає `host.docker.internal:0`.

### Повністю чиста збірка

Наступна команда видаляє build/install/log volumes і весь кеш workspace:

```powershell
docker compose -f compose.yaml -f compose.arm64.yaml down -v
```

Використовуйте її лише коли справді потрібна чиста повторна збірка.

