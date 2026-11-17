@echo off
chcp 65001 >nul
setlocal EnableExtensions

set "SRC=%~dp0"
set "SRC=%SRC:~0,-1%"
set "FROMSHARE=0"

if "%SRC:~0,2%"=="\\" goto :fromshare
goto :local

:fromshare
set "FROMSHARE=1"
echo ============================================================
echo  检测到在共享盘上运行：%SRC%
echo  先同步到本地副本，再在本地构建（obj/bin/dist 绝不写共享）
echo ============================================================
set "LOCAL=C:\work\MyCode\mpv.net"
if not exist "C:\work\MyCode" mkdir "C:\work\MyCode" >nul 2>&1
robocopy "%SRC%" "%LOCAL%" /E /XD obj bin dist _deps Output /XF _build.log /NFL /NDL /NJH /NJS /NP /R:1 /W:1 >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 (
  echo [错误] 同步源码失败 rc=%RC%
  echo        请确认能访问共享：net use \\192.168.31.48\Mycode /user:MRNONG\share MyCode2026
  if not defined BUILD_NO_PAUSE pause
  exit /b 1
)
echo [已同步] %LOCAL%
cd /d "%LOCAL%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCAL%\build.ps1" %*
goto :finish

:local
cd /d "%SRC%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%\build.ps1" %*

:finish
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo [OK] 构建完成
  if "%FROMSHARE%"=="1" (
    if exist "%LOCAL%\dist" (
      echo [回传] 把产物复制回共享：%SRC%\dist
      xcopy /Y "%LOCAL%\dist\*.zip" "%SRC%\dist\" >nul 2>&1
      xcopy /Y "%LOCAL%\dist\*-setup-x64.exe" "%SRC%\dist\" >nul 2>&1
      if not errorlevel 1 echo [回传完成]
    )
  )
) else (
  echo [FAILED] exit code %RC%
  if "%FROMSHARE%"=="1" echo       日志：%LOCAL%\_build.log
)
if not defined BUILD_NO_PAUSE pause
exit /b %RC%
