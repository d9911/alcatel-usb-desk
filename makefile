.DEFAULT_GOAL := help
.PHONY: help init setup test test-ui test-desktop-usb test-usb check run phone camera

POWERSHELL ?= powershell.exe
PS_FLAGS := -NoLogo -NoProfile -ExecutionPolicy Bypass

help:
	@echo make init   - Download and verify the pinned scrcpy/ADB tools
	@echo make test   - Run offline regression tests
	@echo make test-ui - Check desktop layout, languages and embedded logs without USB
	@echo make test-desktop-usb - Check a separate read-only USB window and live logs
	@echo make test-usb - Check scroll control startup/cleanup on a connected phone
	@echo make check  - Show connected USB device diagnostics
	@echo make run    - Open Alcatel USB Desk
	@echo make phone  - Open the phone screen with vertical wheel scrolling
	@echo make camera - Open the camera preview

# Подготовить и проверить scrcpy, ADB и поддержку колёсика
# No OBS, Camo, DroidCam, Python, Node.js or paid packages are installed.
init setup:
	$(POWERSHELL) $(PS_FLAGS) -File Setup.ps1

# Тесты без телефона
test:
	$(POWERSHELL) $(PS_FLAGS) -File tests/Run-Tests.ps1

test-ui:
	$(POWERSHELL) $(PS_FLAGS) -STA -File Alcatel.ps1 -SmokeTest

test-desktop-usb:
	$(POWERSHELL) $(PS_FLAGS) -File tests/Test-DesktopUsb.ps1

# Проверить управляющий канал подключённого телефона
test-usb:
	$(POWERSHELL) $(PS_FLAGS) -File tests/Test-UsbScroll.ps1

# USB-диагностика
check:
	$(POWERSHELL) $(PS_FLAGS) -File Alcatel.ps1 -Action Check

# Открыть приложение
run:
	$(POWERSHELL) $(PS_FLAGS) -STA -File Alcatel.ps1 -Action App

phone:
	$(POWERSHELL) $(PS_FLAGS) -STA -File Alcatel.ps1 -Action Phone

camera:
	$(POWERSHELL) $(PS_FLAGS) -File Alcatel.ps1 -Action Camera
