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

Збірка під Ubuntu не є доказом сумісності з Raspberry Pi OS.

## 2. Обов’язкові перевірки

### 2.1. Статичні перевірки репозиторію

1. Формат версії продукту — `MAJOR.MINOR.FEATURE.PATCH`.
2. Версія CMake, runtime-тег, `CHANGELOG.md` і release-тег узгоджені.
3. Усі `package.xml` є валідними XML і використовують узгоджену
   трикомпонентну ROS-версію.
4. `git diff --check` не виявляє whitespace-помилок.
5. У робочому дереві немає випадково доданих build/output-артефактів.

### 2.2. Перевірки Docker-середовища

1. Docker Desktop доступний.
2. Buildx підтримує `linux/arm64`.
3. Базовий образ — Debian 13 Trixie.
4. `dpkg --print-architecture` повертає `arm64`.
5. `pkg-config --modversion opencv4` повертає `4.10.0`.

### 2.3. Збірка

1. IROS2_0 завантажується з офіційного GitHub Release, а його SHA-256 і Debian-версія перевіряються до збірки VINS.
2. Відсутній у IROS2_0 `cv_bridge` збирається з зафіксованого upstream Git SHA та встановлюється в `/opt/vins`.
3. Усі пакети VINS збираються послідовно в режимі `Release`.
4. Збірка завершується без помилок.
5. Release install prefix формується в `/opt/vins`.

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

## 4. Команди

Повний Docker test gate у Windows PowerShell:

```powershell
.\tools\test-release.ps1 -Version 1.0.1.7
```

Збірка `.deb` після test gate:

```powershell
.\tools\build-arm64-deb.ps1 -Version 1.0.1.7
```
