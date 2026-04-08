@echo off
setlocal
chcp 65001 > nul

set "AIBOT_SUBST_DRIVE="
for %%D in (X W V U T S R Q P O N M L K J I) do (
  if not exist "%%D:\" (
    set "AIBOT_SUBST_DRIVE=%%D:"
    goto :drive_found
  )
)

echo No free drive letter available for desktop build.
exit /b 1

:drive_found
subst %AIBOT_SUBST_DRIVE% "%PROJECT_DIR%" > nul
if errorlevel 1 (
  echo Failed to map %PROJECT_DIR% to %AIBOT_SUBST_DRIVE%.
  exit /b 1
)

set "PROJECT_DIR=%AIBOT_SUBST_DRIVE%\"
set "FLUTTER_EPHEMERAL_DIR=%PROJECT_DIR%windows\flutter\ephemeral"
set "PACKAGE_CONFIG=%PROJECT_DIR%.dart_tool\package_config.json"
set "AIBOT_WRAPPER_SRC=%FLUTTER_ROOT%\bin\cache\artifacts\engine\windows-x64\cpp_client_wrapper"

if not exist "%FLUTTER_EPHEMERAL_DIR%\cpp_client_wrapper" (
  mkdir "%FLUTTER_EPHEMERAL_DIR%\cpp_client_wrapper"
)
xcopy "%AIBOT_WRAPPER_SRC%\*" "%FLUTTER_EPHEMERAL_DIR%\cpp_client_wrapper\" /E /I /Y > nul

"%FLUTTER_ROOT%\packages\flutter_tools\bin\tool_backend.bat" %*
set "AIBOT_BACKEND_EXIT=%ERRORLEVEL%"
subst %AIBOT_SUBST_DRIVE% /D > nul
exit /b %AIBOT_BACKEND_EXIT%
