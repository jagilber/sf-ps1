%cd%
set
%1
%scripts%
%codeVersion%
rem set codeVersion=1.0.0
whoami
cd ..\%Fabric_ServicePackageName%.%Fabric_CodePackageName%.%codeVersion%
set scriptFile=%cd%\sf-script-manager.ps1
rem powershell.exe -nologo -noprofile -noninteractive -windowstyle hidden -file %scriptFile% %scripts%
powershell.exe -nologo -noprofile -file "%scriptFile%" -scripts "%scripts%"