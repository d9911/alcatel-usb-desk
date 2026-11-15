# Alcatel USB Desk

[English](README.md) · [Русский](README.ru.md) · [Español](README.es.md)

Удалённое управление по USB, зеркалирование экрана и предпросмотр камеры
**Alcatel 1S (5024D_RU), Android 9** с компьютера Windows на основе [scrcpy].

## Возможности

- Экран телефона с управлением мышью, клавиатурой и прокруткой колёсиком.
- Предпросмотр штатной камеры с обрезкой и поворотом; по умолчанию — 90°.
- Настройка физической клавиатуры Android для RU / EN; смена — Ctrl+Пробел.
- Выбор устройства, диагностика и живой журнал подключения в окне приложения.
- Английский по умолчанию, русский на выбор; испанский включается отдельно.
- Локальное сохранение устройства, языка и параметров камеры.

Предпросмотр камеры может засыпать — активируй его на телефоне. Для видеозвонков
захвати окно **Alcatel Camera USB** в OBS и отдельно включи OBS Virtual Camera.

## Запуск

Нужны Windows 10/11 x64, Windows PowerShell 5.1 и USB-кабель с передачей данных.
Проверено на Windows 11 с указанным телефоном. Включи USB-отладку на Android
и подтверди запрос подключения компьютера.

Выполни из папки проекта; установка нужна при первом использовании:

```powershell
.\Setup.cmd
.\Start.cmd
```

Установка скачивает и проверяет закреплённый комплект scrcpy/ADB из
[dependencies.json](dependencies.json). `Start.cmd` открывает приложение.
Язык выбирается справа вверху, сохраняется сразу и восстанавливается при
следующем запуске, включая русский. Нажимать Save settings для языка не нужно.
Настройки хранятся в `config/settings.local.json`, журналы — в `logs/`.
Они исключены из Git.

## Технологии и навыки

- **Языки:** PowerShell 5.1, C#; CMD и GNU Make для запуска и установки.
- **Библиотеки интерфейса:** .NET Framework, Windows Forms и System.Drawing.
- **Инструменты USB:** scrcpy 5.0.1 и Android Debug Bridge (ADB).
- **Навыки:** фоновые задачи, ввод USB/HID, потоковое чтение журналов UTF-8.
- **Скилл разработки:** Codex `code-work` — реализация и проверки.

Отдельный C# SDK, Python и Node.js не нужны. При наличии GNU Make доступны
`make init`, `make run`, `make test`, `make test-ui`. Все цели — в `make help`.

## Ключевые слова

Alcatel USB Desk, Alcatel 1S, 5024D_RU, Android 9, Windows, scrcpy, ADB,
USB remote control, screen mirroring, Android camera preview.
Алкатель, управление телефоном с ПК, удалённое управление по USB,
зеркалирование экрана Android, камера телефона по USB.

## Лицензия

[MIT](LICENSE) — Denis Gutsuliak ([d9911]). scrcpy использует [Apache-2.0].
ADB, SDL, FFmpeg, libusb и остальные компоненты сохраняют свои лицензии;
установка сохраняет исходный `LICENSE.txt` в папке скачанных инструментов.
Проект независимый и не связан с Alcatel/TCL или Genymobile.

[scrcpy]: https://github.com/Genymobile/scrcpy
[d9911]: https://github.com/d9911
[Apache-2.0]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/LICENSE
