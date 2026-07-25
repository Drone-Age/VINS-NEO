# Стандарт передрелізного тестування

Цей стандарт визначає обов’язковий test gate перед створенням або
перенесенням релізного Git-тега VINS-NEO.

## 1. Цільове середовище

Офіційний Raspberry Pi release збирається для:

- Debian 13 Trixie;
- архітектури `arm64`;
- OpenCV 4.10;
- ROS 2 Jazzy з пакета IROS2_0 `iros2-0_0.1.1-1+deb13_arm64.deb`;
- C++17 і системного toolchain Debian 13.

Збірка релізного `.deb` і всі обов’язкові передрелізні тести виконуються лише
на нативній цільовій ARM64-системі. Збірка під Ubuntu, у Docker, через
ARM64-емуляцію на x86-64 або cross-compilation не є доказом сумісності з
Raspberry Pi OS і не може пройти release gate.

Docker та CI дозволені лише як додаткові перевірки під час розробки. Їхні
результати не замінюють жодної обов’язкової нативної перевірки.

## 2. Обов’язкові перевірки

### 2.1. Статичні перевірки репозиторію

1. Формат версії продукту — `MAJOR.MINOR.FEATURE.PATCH`.
2. Версія CMake, runtime-тег, `CHANGELOG.md` і release-тег узгоджені.
3. `config/releases/<RELEASE_TAG>.env` входить до того самого release-коміту
   та фіксує URL, Debian-версію і SHA-256 обраного iROS2 asset.
4. Усі `package.xml` є валідними XML і використовують узгоджену
   трикомпонентну ROS-версію.
5. `tools/check-release-metadata.ps1` успішно перевіряє release-коміт.
6. `git diff --check` не виявляє whitespace-помилок.
7. У робочому дереві немає випадково доданих build/output-артефактів.

### 2.2. Перевірки нативного середовища

1. Збірка виконується безпосередньо на підтримуваній Raspberry Pi /
   нативній ARM64-системі, а не в контейнері.
2. `uname -m` повертає `aarch64`.
3. `dpkg --print-architecture` повертає `arm64`.
4. `/etc/os-release` відповідає затвердженій Raspberry Pi OS / Debian 13.
5. `pkg-config --modversion opencv4` повертає затверджену версію OpenCV.
6. `dpkg-query` підтверджує затверджену версію `iros2-0`.
7. Усі build/test команди та їхні результати зберігаються у протоколі релізу.

### 2.3. Збірка

1. Збірка запускається на нативній ARM64-системі без Docker, емуляції та
   cross-compilation.
2. IROS2_0 завантажується з офіційного GitHub Release, а його SHA-256 і Debian-версія перевіряються до збірки VINS.
3. Відсутній у IROS2_0 `cv_bridge` збирається з зафіксованого upstream Git SHA та встановлюється в `/opt/vins`.
4. Усі пакети VINS збираються послідовно в режимі `Release`.
5. Збірка завершується без помилок.
6. Release install prefix формується в `/opt/vins`.
7. `.deb`, створений в іншому середовищі, заборонено повторно використовувати
   або публікувати як результат цієї перевірки.

### 2.4. Автоматичні тести

1. Виконується `colcon test`.
2. `colcon test-result --verbose` не містить failures.
3. `vins_estimator --version` повертає очікувані версію і тег.
4. Усі ELF-файли перевіряються через `ldd`.
5. Жодна бібліотека не повинна мати стан `not found`.

### 2.5. Перевірка пакета

1. Ім’я файла містить версію продукту й архітектуру.
2. Поля `Version` та `Architecture` у control archive правильні.
3. Пакет не залежить від Ubuntu-only пакетів `ros-jazzy-*`.
4. Пакет містить `/opt/vins` і profile script, залежить від точної версії `iros2-0` та не дублює underlay `/opt/iros2_0/jazzy`.
5. Для файла обчислюється SHA-256.

### 2.6. Перевірка на Raspberry Pi

1. Пакет встановлюється через `apt install ./<package>.deb`.
2. `dpkg -s vins-mono-ros2` повертає `install ok installed`.
3. Після sourcing profile доступний `ros2`.
4. `dpkg-query` підтверджує встановлення `iros2-0` версії `0.1.1-1+deb13`.
5. ROS знаходить `vins_estimator` і `feature_tracker`.
6. `vins_estimator --version` відповідає релізу.
7. `ldd` на Raspberry не показує відсутніх бібліотек.

## 3. Критерій проходження

Реліз дозволений лише тоді, коли всі автоматизовані перевірки завершилися
успішно, а перевірка на Raspberry Pi задокументована. Будь-який пропущений
тест фіксується як блокер, а не як успішний результат.

## 4. Команди та протокол

Релізні build/test команди виконує `tools/native-release.sh` лише в shell
нативної ARM64-системи. Windows-скрипт
`tools/invoke-native-release.ps1` є SSH-диспетчером: він перевіряє цільовий
хост, передає архів вибраної Git-ревізії в ізольований каталог і запускає там
нативний скрипт. Він не виконує build/test локально.

Повний gate із Windows PowerShell:

```powershell
.\tools\invoke-native-release.ps1 `
  -InstallDependencies -InstallTest -DatasetTest
```

Тільки безпечна перевірка доступності та параметрів середовища:

```powershell
.\tools\invoke-native-release.ps1 -PreflightOnly
```

Без `-GitRef` вибирається найновіший версійний тег, доступний із `HEAD`.
Залежності конкретного релізу фіксуються у
`config/releases/<RELEASE_TAG>.env`. Параметри хоста читаються з
ігнорованого Git файлу `config/native/native.env`.

Обрана iROS2 не визначається під час збірки. Вона повинна бути зафіксована в
release-коміті. Перед створенням коміту staged metadata перевіряється командою:

```powershell
.\tools\check-release-metadata.ps1 `
  -Index -ReleaseTag <RELEASE_TAG> -VerifyAsset
```

Windows PowerShell scripts `tools/test-release.ps1` і
`tools/build-arm64-deb.ps1`, Docker Compose, WSL, емуляція та
cross-compilation не є релізним workflow.
