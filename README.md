# Alcatel USB Desk

[English](README.md) · [Русский](README.ru.md) · [Español](README.es.md)

USB remote control, screen mirroring and camera preview for
**Alcatel 1S (5024D_RU), Android 9** on Windows, built around [scrcpy].

## Features

- Phone screen with mouse, keyboard and vertical wheel scrolling.
- Stock camera preview with crop and rotation; the default is 90°.
- Android physical keyboard setup for RU / EN; switch with Ctrl+Space.
- Device selection, diagnostics and live connection logs inside the app.
- English by default, Russian selectable; Spanish is optional.
- Local preferences for the device, language and camera parameters.

The camera preview can go idle; reactivate it on the phone. For video calls,
capture **Alcatel Camera USB** in OBS and enable OBS Virtual Camera separately.

## Start

Windows 10/11 x64, Windows PowerShell 5.1 and a USB data cable are required.
Tested on Windows 11 with the phone above. Enable USB debugging on Android
and approve the computer's connection prompt.

Run in the project folder; setup is needed on first use:

```powershell
.\Setup.cmd
.\Start.cmd
```

Setup downloads and verifies the pinned scrcpy/ADB bundle from
[dependencies.json](dependencies.json). `Start.cmd` opens the desktop.
Select the language at the top right. Changes are saved immediately and restored
on the next launch, including Russian; no Save settings click is needed.
Settings and logs stay in ignored `config/settings.local.json` and `logs/`.

## Technologies and skills

- **Languages:** PowerShell 5.1, C#; CMD and GNU Make for launch/setup.
- **UI libraries:** .NET Framework, Windows Forms and System.Drawing.
- **USB tools:** scrcpy 5.0.1 and Android Debug Bridge (ADB).
- **Engineering:** background tasks, USB/HID input and incremental UTF-8 logs.
- **Development skill:** Codex `code-work` for implementation and checks.

No separate C# SDK, Python or Node.js is required. Optional GNU Make commands:
`make init`, `make run`, `make test`, `make test-ui`.
`make help` lists all targets.

## Search keywords

Alcatel USB Desk, Alcatel 1S, 5024D_RU, Android 9, Windows, scrcpy, ADB,
USB remote control, screen mirroring, Android camera preview.
Алкатель, управление телефоном с ПК, удалённое управление по USB,
зеркалирование экрана Android, камера телефона по USB.

## License

[MIT](LICENSE) — Denis Gutsuliak ([d9911]). scrcpy uses [Apache-2.0].
ADB, SDL, FFmpeg, libusb and other bundled components keep their own licenses;
setup preserves the upstream `LICENSE.txt` in the downloaded tool directory.
This independent project is not affiliated with Alcatel/TCL or Genymobile.

[scrcpy]: https://github.com/Genymobile/scrcpy
[d9911]: https://github.com/d9911
[Apache-2.0]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/LICENSE
