@echo on
echo %cd%
set
echo %1
echo %scripts%
echo %codeVersion%
rem set codeVersion=1.0.0
whoami
cd ..\%Fabric_ServicePackageName%.%Fabric_CodePackageName%.%codeVersion%
set scriptManagerFile=%cd%\sf-script-manager.ps1

if "%1"=="setupentrypoint" (
	echo setupentrypoint
	powershell.exe -executionPolicy Bypass -nologo -noprofile -file "%scriptManagerFile%" -scripts "%setupScripts%"
)

if "%1"=="entrypoint" (
	echo entrypoint
	rem powershell.exe -executionPolicy Bypass -nologo -noprofile -file "%scriptManagerFile%" -scripts "%scripts%" -doNotReturn
	powershell.exe -executionPolicy Bypass -nologo -file "%scriptManagerFile%" -scripts "%scripts%" -doNotReturn
)

