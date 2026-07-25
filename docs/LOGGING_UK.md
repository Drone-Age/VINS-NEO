# Журналювання та діагностика estimator

Документ відповідає функціоналу VINS-MONO-ROS2 `1.0.2.0`.

## 1. Принцип роботи

Estimator використовує стандартну інфраструктуру ROS 2 logging. Повідомлення
надходять:

- у консоль;
- у ROS log-файли;
- у `/rosout`, якщо цей канал не вимкнено.

Типовий префікс:

```text
[INFO] [1784811810.265533099] [vins_estimator.vins_estimator]:
```

Число після `[INFO]` — час формування повідомлення ROS logger. Короткі
runtime-статуси не дублюють sensor timestamp.

## 2. Рівні

Параметр `logging.level` підтримує:

| Значення | Призначення |
|---|---|
| `DEBUG` | Деталі оптимізації та внутрішньої діагностики |
| `INFO` | Стани, telemetry, версія та результат ініціалізації |
| `WARNING` або `WARN` | Відхилення, що допускають продовження роботи |
| `ERROR` | Помилки estimator |
| `CRITICAL` або `FATAL` | Критичні стани |

Фільтрація стандартна: обраний рівень пропускає повідомлення цього та вищих
рівнів. Наприклад, `WARNING` приховує `DEBUG` та `INFO`.

## 3. Мінімальний період

`logging.period_ms` задає мінімальний інтервал між періодичними INFO-статусами
у мілісекундах.

Поточне значення за замовчуванням:

```python
'logging.period_ms': 2000
```

Рекомендації:

| Період | Застосування |
|---:|---|
| `500–1000` мс | Інтерактивна діагностика |
| `2000` мс | Звичайна робота |
| `5000–10000` мс | Тривалий запис із мінімальним логом |
| `0` | Без обмеження; може створити дуже великий потік повідомлень |

На Raspberry не рекомендовано встановлювати `0`, окрім короткої діагностики.

## 4. Налаштування

Поточні значення задаються у:

```text
vins_estimator/launch/euroc.launch.py
```

Фрагмент:

```python
parameters=[{
    'config_file': config_path,
    'vins_folder': vins_path,
    'logging.level': 'INFO',
    'logging.period_ms': 2000
}]
```

Після зміни launch-файла:

```bash
cd ~/vins_ws
source /opt/iros2_0/jazzy/setup.bash
colcon build \
  --symlink-install \
  --executor sequential \
  --packages-select vins_estimator
source install/setup.bash
```

## 5. Формати INFO

### Очікування даних

```text
state=WAITING imu_status=MISSING imu_messages=0 camera_status=MISSING camera_feature_messages=0
```

Статуси:

- `MISSING` — повідомлення цього типу ще не надходили;
- `RECEIVING` — отримано щонайменше одне повідомлення.

Лічильники накопичуються від запуску або restart estimator.

### Ініціалізація

```text
state=INITIALIZING frames=10/10 feat=240 ms=0.3 imu=LOW_EXCITATION vision=LOW_MOTION
```

Поля недостатності додаються лише за наявності відповідної умови.

### Tracking

```text
state=TRACKING pos=[5.69 3.04 1.19] ypr=[8.94 32.20 165.92] vel=[7.35 4.21 -0.81] feat=141 td=0.0016 ms=16.0
```

Формат навмисно скорочено, щоб рядок уміщувався у типовий термінал.

### Переходи стану

```text
[STATE END] INITIALIZING
[STATE BEGIN] TRACKING
```

Перехід завжди завершує попередній стан і починає новий окремими рядками.

### Повна ініціалізація

Після успішного переходу до TRACKING виводиться багаторядковий блок із:

- розміром заповненого вікна;
- кількістю tracked features;
- метричним масштабом, IMU excitation і visual parallax;
- gravity до вирівнювання світової системи та початковою орієнтацією;
- позицією та YPR;
- швидкістю;
- accelerometer і gyroscope bias;
- вектором gravity;
- time offset і режимом його оцінювання;
- агрегованою статистикою triangulated feature depths;
- кількістю камер;
- режимом extrinsic estimation;
- джерелом extrinsic-параметрів;
- extrinsic translation і orientation для кожної камери.

## 6. Кольори

Launch-файл встановлює:

```text
RCUTILS_COLORIZED_OUTPUT=1
```

У сумісному терміналі:

- `WARN` — жовтий;
- `ERROR` — червоний.

Колір не є частиною тексту повідомлення і може бути відсутнім при
перенаправленні у файл або в інтерфейсі без ANSI color.

## 7. Внутрішній Ceres logging

На INFO-рівні progress та verbose diagnostics Ceres приглушуються. Це
запобігає появі низькорівневих повідомлень на кшталт
`block_sparse_matrix` або `detect_structure`.

Для дослідження оптимізації використовуйте `DEBUG`, але враховуйте збільшення
обсягу журналу та додаткове навантаження.

## 8. Файли журналів

ROS 2 повідомляє каталог при запуску:

```text
[INFO] [launch]: All log files can be found below ...
```

Типово це:

```text
~/.ros/log/
```

Каталог можна змінити через `ROS_LOG_DIR`, як описано в
[офіційній документації ROS 2](https://docs.ros.org/en/jazzy/Concepts/Intermediate/About-Logging.html).

## 9. Практичні профілі

Звичайна робота:

```python
'logging.level': 'INFO',
'logging.period_ms': 2000
```

Пошук проблем ініціалізації:

```python
'logging.level': 'DEBUG',
'logging.period_ms': 500
```

Тривалий автономний запуск:

```python
'logging.level': 'WARNING',
'logging.period_ms': 10000
```

За рівня `WARNING` періодичні INFO-статуси не виводяться незалежно від
`logging.period_ms`.

## 10. Додаткові англомовні матеріали

- [ROS 2 logging concepts](https://docs.ros.org/en/jazzy/Concepts/Intermediate/About-Logging.html)
- [ROS 2 logging tutorial](https://docs.ros.org/en/jazzy/Tutorials/Demos/Logging-and-logger-configuration.html)
- [ROS 2 command-line logging configuration](https://docs.ros.org/en/jazzy/Concepts/Intermediate/About-Logging.html#configuration)
- [Ceres Solver documentation](https://ceres-solver.readthedocs.io/)

