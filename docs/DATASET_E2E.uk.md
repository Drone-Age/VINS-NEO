# Dataset e2e через DataSetsManager

VINS-NEO відповідає за ROS 2 launch, runtime-перевірки, cleanup і evidence.
DataSetsManager Client відповідає за визначення dataset/profile, незмінні
артефакти, контрольні суми та перевірену конфігурацію VINS.

Перший підтриманий контракт: dataset `iv.dev.4.ff.1`, runtime profile `dev_04`,
implementation `vins-neo` і suite `smoke`. Профіль береться з dataset manifest.
Профіль, заданий вручну, є лише assertion.

## Development-запуск на Ubuntu 24.04 AMD64

Встановіть DataSetsManager Client 1.1.0 або використайте його development
checkout. Виділений ключ `user` зберігайте лише в оточенні процесу — не в
команді, файлі, журналі або каталозі evidence:

```bash
export DSM_SERVER_TOKEN='<dedicated e2e user key>'
dsm-client prepare-run iv.dev.4.ff.1 \
  --implementation vins-neo --suite smoke --format rosbag2 \
  --server-url https://datasetsmanager.drone-age.org \
  > /tmp/iv.dev.4.ff.1-run-manifest.json

python3 tools/dataset_e2e.py \
  --dataset-id iv.dev.4.ff.1 --suite smoke \
  --dsm-server-url https://datasetsmanager.drone-age.org \
  --evidence-dir evidence/iv.dev.4.ff.1-amd64
```

Runner може викликати `dsm-client prepare-run` безпосередньо, як у другій
команді. Він також приймає готовий manifest через `--run-manifest`; у цьому
режимі DSM token не потрібний.

Локальна послідовність розробки:

```bash
docker compose build
docker compose run --rm vins build
docker compose run --rm vins test
# У репозиторії DataSetsManager Client виконайте contract та fixture-integration tests.
# Потім запустіть tools/dataset_e2e.py з реальним незмінним dataset.
```

Комбінований launch — `vins_estimator vins_neo.launch.py`. Він передає один
`config_file` обом вузлам і відкриває `vins_folder`, `use_sim_time`, `log_level`
та `logging_period_ms`. Чинні окремі launch-файли зберігають EuRoC як default.

## Приймання та evidence

`dataset-e2e-result.json` має `PASS` лише коли:

- `ros2 bag info` приймає артефакт, який не є fixture;
- camera та IMU topics існують у bag, мають очікувані типи й активні в runtime;
- feature tracker та estimator працюють до завершення playback;
- отримано щонайменше 10 odometry messages;
- timestamps odometry монотонні, а position/orientation мають скінченні значення.

Результат фіксує dataset ID, profile, artifact version і source/content SHA-256,
SHA-256 конфігурації, suite version та DSM Client version. Counts, duration,
Delta XY/XYZ, CPU time і peak RSS є baseline; Delta не блокує тест, доки ground
truth відсутній. Помилки authentication, checksum/profile mismatch, відсутні
topics, раннє завершення, timeout і відсутність odometry дають явний `FAIL`.
Cleanup виконується після PASS, FAIL, timeout і переривання.

Ubuntu 24.04 AMD64 створює evidence класу `development`. Лише повторний запуск
на native Debian 13 ARM64 поза Docker може створити evidence класу `release`.

## Передавання на Raspberry Pi без token

Підготуйте run manifest і завантажте/перевірте artifact на host через HTTPS.
Укажіть `DATASET_RUN_MANIFEST` в ignored `config/native/native.env`, після чого
виконайте:

```powershell
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -IntegrationTest -DatasetTest
```

Dispatcher передає на Pi перевірені artifact, configuration і manifest із
відносними шляхами. Native workflow активує `iros2j` із `/opt/iros2j` перед
VINS overlay. `DSM_SERVER_TOKEN` не передається. `--dataset` та
`--vins-config` залишаються deprecated expert overrides на один цикл
сумісності.
