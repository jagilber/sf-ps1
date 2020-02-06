@echo on
echo %cd%
set
echo %1
echo %scripts%
echo %codeVersion%
rem set codeVersion=1.0.0
whoami
cd ..\%Fabric_ServicePackageName%.%Fabric_CodePackageName%.%codeVersion%

if "%1"=="entrypoint" (
	echo entrypoint, pausing
	pause
	rem exit
)

set scriptFile=%cd%\sf-script-manager.ps1
powershell.exe -nologo -noprofile -file "%scriptFile%"