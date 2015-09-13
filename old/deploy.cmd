@if "%SCM_TRACE_LEVEL%" NEQ "4" @echo off

:: ----------------------
:: KUDU Deployment Script
:: Version: 0.1.11
:: ----------------------

:: Prerequisites
:: -------------

:: Verify node.js installed
where node 2>nul >nul
IF %ERRORLEVEL% NEQ 0 (
  echo Missing node.js executable, please install node.js, if already installed make sure it can be reached from current environment.
  goto error
)

:: Setup
:: -----

setlocal enabledelayedexpansion

SET ARTIFACTS=%~dp0%..\artifacts

IF NOT DEFINED DEPLOYMENT_SOURCE (
  SET DEPLOYMENT_SOURCE=%~dp0%.
)

IF NOT DEFINED DEPLOYMENT_TARGET (
  SET DEPLOYMENT_TARGET=%ARTIFACTS%\wwwroot
)

IF NOT DEFINED NEXT_MANIFEST_PATH (
  SET NEXT_MANIFEST_PATH=%ARTIFACTS%\manifest

  IF NOT DEFINED PREVIOUS_MANIFEST_PATH (
    SET PREVIOUS_MANIFEST_PATH=%ARTIFACTS%\manifest
  )
)

IF NOT DEFINED KUDU_SYNC_CMD (
  :: Install kudu sync
  echo Installing Kudu Sync
  call npm install kudusync -g --silent
  IF !ERRORLEVEL! NEQ 0 goto error

  :: Locally just running "kuduSync" would also work
  SET KUDU_SYNC_CMD=%appdata%\npm\kuduSync.cmd
)

SET DEPLOYMENT_TEMP=%temp%\___deployTemp\install

IF DEFINED CLEAN_LOCAL_DEPLOYMENT_TEMP (
  IF EXIST "%DEPLOYMENT_TEMP%" rd /s /q "%DEPLOYMENT_TEMP%"
)

IF NOT EXIST "%DEPLOYMENT_TEMP%" mkdir "%DEPLOYMENT_TEMP%"

goto Deployment

:: Utility Functions
:: -----------------

:SelectNodeVersion

IF DEFINED KUDU_SELECT_NODE_VERSION_CMD (
  :: The following are done only on Windows Azure Websites environment
  call %KUDU_SELECT_NODE_VERSION_CMD% "%DEPLOYMENT_SOURCE%" "%DEPLOYMENT_TARGET%" "%DEPLOYMENT_TEMP%"
  IF !ERRORLEVEL! NEQ 0 goto error

  IF EXIST "%DEPLOYMENT_TEMP%\__nodeVersion.tmp" (
    SET /p NODE_EXE=<"%DEPLOYMENT_TEMP%\__nodeVersion.tmp"
    IF !ERRORLEVEL! NEQ 0 goto error
  )
  
  IF EXIST "%DEPLOYMENT_TEMP%\__npmVersion.tmp" (
    SET /p NPM_JS_PATH=<"%DEPLOYMENT_TEMP%\__npmVersion.tmp"
    IF !ERRORLEVEL! NEQ 0 goto error
  )

  IF NOT DEFINED NODE_EXE (
    SET NODE_EXE=node
  )

  SET NPM_CMD="!NODE_EXE!" "!NPM_JS_PATH!"
) ELSE (
  SET NPM_CMD=npm
  SET NODE_EXE=node
)

goto :EOF

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Deployment
:: ----------

:Deployment
echo Handling node.js deployment.

:: 1. KuduSync
IF /I "%IN_PLACE_DEPLOYMENT%" NEQ "1" (
  call :ExecuteCmd "%KUDU_SYNC_CMD%" -v 50 -f "%DEPLOYMENT_SOURCE%" -t "%DEPLOYMENT_TEMP%" -n "%NEXT_MANIFEST_PATH%" -p "%PREVIOUS_MANIFEST_PATH%" -i ".git;.hg;.deployment;deploy.cmd"
  IF !ERRORLEVEL! NEQ 0 goto error
)

:: 2. Select node version
call :SelectNodeVersion

:: 3. Install npm packages
call :ExecuteCmd !NPM_CMD! install -g rimraf

IF EXIST "%DEPLOYMENT_TEMP%\package.json" (
  pushd "%DEPLOYMENT_TEMP%"

  IF EXIST ".\build" (
	ECHO Cleaning build...
    call :ExecuteCmd rimraf .\build
  )

  echo Temp dir is %DEPLOYMENT_TEMP%
  IF /I "%CLEAN_NODE_MODULES%" EQU "1" (
    ECHO Cleaning node_modules...
    call :ExecuteCmd rimraf .\node_modules
  ) ELSE (
    ECHO Not cleaning node_modules - set CLEAN_NODE_MODULES to 1 if you want
  )
  IF /I "%CLEAN_NPM_CACHE%" EQU "1" (
    ECHO Cleaning npm cache...
    call :ExecuteCmd !NPM_CMD! cache clean
  ) ELSE (
    ECHO Not cleaning npm cache - set CLEAN_NPM_CACHE to 1 if you want
  )
  echo Updating npm...
  call :ExecuteCmd !NPM_CMD! install -g npm
  call :ExecuteCmd !NPM_CMD! install replace
  call :ExecuteCmd "!NODE_EXE!" ./node_modules/replace/bin/replace -q http://npm:8080 https://registry.npmjs.org npm-shrinkwrap.json
  echo npm install...
  call :ExecuteCmd !NPM_CMD! install --production
  IF !ERRORLEVEL! NEQ 0 goto error
  ECHO npm install done
  popd
)

:: 4. Copy content
IF /I "%IN_PLACE_DEPLOYMENT%" NEQ "1" (
  ECHO Copying content from %DEPLOYMENT_TEMP%\build to %DEPLOYMENT_TARGET%
  call :ExecuteCmd "%KUDU_SYNC_CMD%" -v 50 -f "%DEPLOYMENT_TEMP%\build" -t "%DEPLOYMENT_TARGET%" -n "%NEXT_MANIFEST_PATH%" -p "%PREVIOUS_MANIFEST_PATH%" -i ".git;.hg;.deployment;deploy.cmd"
  IF !ERRORLEVEL! NEQ 0 goto error
)


::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:: Post deployment stub
IF DEFINED POST_DEPLOYMENT_ACTION call "%POST_DEPLOYMENT_ACTION%"
IF !ERRORLEVEL! NEQ 0 goto error

goto end

:: Execute command routine that will echo out when error
:ExecuteCmd
setlocal
set _CMD_=%*
call %_CMD_%
if "%ERRORLEVEL%" NEQ "0" echo Failed exitCode=%ERRORLEVEL%, command=%_CMD_%
exit /b %ERRORLEVEL%

:error
endlocal
echo An error has occurred during web site deployment.
call :exitSetErrorLevel
call :exitFromFunction 2>nul

:exitSetErrorLevel
exit /b 1

:exitFromFunction
()

:end
endlocal
echo Finished successfully.
