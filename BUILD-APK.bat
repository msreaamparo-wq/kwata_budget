@echo off
setlocal
cd /d "%~dp0"

set "FLUTTER_CMD=flutter"
where flutter >nul 2>nul
if errorlevel 1 (
  if exist "D:\flutter\src\flutter\bin\flutter.bat" (
    set "FLUTTER_CMD=D:\flutter\src\flutter\bin\flutter.bat"
  ) else (
    echo ERROR: Flutter was not found.
    echo Install Flutter or add Flutter's bin folder to PATH.
    echo Checked: D:\flutter\src\flutter\bin\flutter.bat
    pause
    exit /b 1
  )
)

echo ==========================================
echo          KWARTA - ANDROID APK BUILD
echo ==========================================
echo.

if not exist "android\settings.gradle.kts" (
  echo Creating Android project files...
  "%FLUTTER_CMD%" create --platforms=android --org com.reaamparo --project-name kwarta_budget_tracker .
  if errorlevel 1 goto failed
)

echo.
echo Checking Flutter and Android setup...
"%FLUTTER_CMD%" doctor
if errorlevel 1 goto failed

echo.
echo Getting Flutter packages...
"%FLUTTER_CMD%" pub get
if errorlevel 1 goto failed

echo.
echo Building release APK...
"%FLUTTER_CMD%" build apk --release
if errorlevel 1 goto failed

echo.
echo ==========================================
echo BUILD SUCCESSFUL!
echo APK: build\app\outputs\flutter-apk\app-release.apk
echo ==========================================
start "" "%CD%\build\app\outputs\flutter-apk"
pause
exit /b 0

:failed
echo.
echo BUILD FAILED. Copy the red terminal error and send it for fixing.
pause
exit /b 1
