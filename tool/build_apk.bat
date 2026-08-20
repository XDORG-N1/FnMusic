@echo off
rem FnMusic 打包脚本（Windows 双击/命令行）。
rem 用法：build_apk.bat [all|release|debug]
rem   默认 all：编译 release + debug。
rem   产物输出到 build\app\outputs\flutter-apk\。

setlocal
cd /d "%~dp0\.."

set "FLUTTER=flutter"
where flutter >nul 2>nul
if errorlevel 1 (
  if exist "C:\dev\flutter\bin\flutter.bat" set "FLUTTER=C:\dev\flutter\bin\flutter.bat"
)

set "MODE=%1"
if "%MODE%"=="" set "MODE=all"

echo ==^> flutter pub get
%FLUTTER% pub get
if errorlevel 1 exit /b 1

if "%MODE%"=="all" goto :all
if "%MODE%"=="release" goto :release
if "%MODE%"=="debug" goto :debug
echo [错误] 未知模式: %MODE% ^(可用: all / release / debug^)
exit /b 1

:release
echo.
echo ==^> flutter build apk --release
%FLUTTER% build apk --release
if errorlevel 1 exit /b 1
goto :done

:debug
echo.
echo ==^> flutter build apk --debug
%FLUTTER% build apk --debug
if errorlevel 1 exit /b 1
goto :done

:all
echo.
echo ==^> flutter build apk --release
%FLUTTER% build apk --release
if errorlevel 1 exit /b 1
echo.
echo ==^> flutter build apk --debug
%FLUTTER% build apk --debug
if errorlevel 1 exit /b 1
goto :done

:done
echo.
echo ==================== 构建完成 ====================
if exist "build\app\outputs\flutter-apk" (
  for %%f in ("build\app\outputs\flutter-apk\*.apk") do (
    echo %%~zf bytes  %%~ff
  )
)
endlocal
