# Alcatel USB Desk

[English](README.md) · [Русский](README.ru.md) · [Español](README.es.md)

Control remoto USB, duplicación de pantalla y vista previa de cámara para
**Alcatel 1S (5024D_RU), Android 9** en Windows, con [scrcpy].

## Funciones

- Pantalla del teléfono con ratón, teclado y desplazamiento con la rueda.
- Vista previa de la cámara con recorte y rotación; 90° por defecto.
- Teclado físico Android para RU / EN; cambio con Ctrl+Espacio.
- Selección del dispositivo, diagnóstico y registro en la propia aplicación.
- Inglés por defecto, ruso seleccionable y español opcional.
- Preferencias locales de dispositivo, idioma y cámara.

La vista previa puede quedar inactiva; actívala en el teléfono.
Para videollamadas, captura **Alcatel Camera USB** en OBS
y activa OBS Virtual Camera por separado.

## Inicio

Requiere Windows 10/11 x64, Windows PowerShell 5.1 y un cable USB de datos.
Probado en Windows 11 con el teléfono indicado. Activa la depuración USB en
Android y autoriza la conexión del ordenador.

Ejecuta desde la carpeta del proyecto; instala las herramientas la primera vez:

```powershell
.\Setup.cmd
.\Start.cmd
```

La instalación descarga y verifica el paquete scrcpy/ADB fijado en
[dependencies.json](dependencies.json). `Start.cmd` abre la aplicación.
El idioma se elige arriba a la derecha, se guarda al cambiarlo y se restaura
al iniciar de nuevo, incluido el ruso. No hace falta pulsar Save settings.
Los ajustes y registros quedan en `config/settings.local.json` y `logs/`,
excluidos de Git.

## Tecnologías y habilidades

- **Lenguajes:** PowerShell 5.1, C#; CMD y GNU Make para inicio e instalación.
- **Bibliotecas de interfaz:** .NET Framework, Windows Forms y System.Drawing.
- **Herramientas USB:** scrcpy 5.0.1 y Android Debug Bridge (ADB).
- **Habilidades:** tareas en segundo plano, entrada USB/HID y registros UTF-8.
- **Skill de desarrollo:** Codex `code-work` para implementación y pruebas.

No requiere un SDK de C# aparte, Python ni Node.js. Con GNU Make opcional:
`make init`, `make run`, `make test`, `make test-ui`.
Todas las tareas: `make help`.

## Palabras clave

Alcatel USB Desk, Alcatel 1S, 5024D_RU, Android 9, Windows, scrcpy, ADB,
USB remote control, screen mirroring, Android camera preview.
Control remoto USB, duplicación de pantalla, cámara Android.
Алкатель, управление телефоном с ПК, зеркалирование экрана Android.

## Licencia

[MIT](LICENSE) — Denis Gutsuliak ([d9911]). scrcpy usa [Apache-2.0].
ADB, SDL, FFmpeg, libusb y los demás componentes conservan sus licencias;
la instalación conserva el `LICENSE.txt` original en la carpeta de herramientas.
Proyecto independiente, sin afiliación con Alcatel/TCL ni Genymobile.

[scrcpy]: https://github.com/Genymobile/scrcpy
[d9911]: https://github.com/d9911
[Apache-2.0]: https://github.com/Genymobile/scrcpy/blob/v5.0.1/LICENSE
