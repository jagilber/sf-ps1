###########################
# sf-ps1 netsh network trace
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [string]$myErrorDescription = ($env:myErrorDescription, "capture network trace with netsh" -ne $null)[0],
    [string]$myDescription = ($env:myDescription, "capture network trace with netsh" -ne $null)[0],
    [string]$traceFile = ($env:traceFile, "$pwd\net.etl" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try{
        $timer = get-date
        write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters : $myDescription`r`n"
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

        if(!$isAdmin){
            write-error "error:restart script as administrator"
            return
        }

        write-host "$(get-date) stopping existing trace`r`n" -ForegroundColor green
        netsh trace stop

        write-host "$(get-date) starting trace" -ForegroundColor green
        netsh trace start capture=yes overwrite=yes maxsize=$maxSizeMb tracefile=$traceFile filemode=circular

        write-host "$(get-date) sleeping $sleepMinutes minutes" -ForegroundColor green
        start-sleep -Seconds ($sleepMinutes * 60)

        write-host "$(get-date) stopping trace" -ForegroundColor green
        netsh trace stop

        if ($error) {
            write-host "ERROR:$myErrorDescription`r`n"
            write-host "$($error | out-string)`r`n"
        }

        write-host "$(get-date) copying files" -ForegroundColor green
        copy net.* ..\log

        write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
        write-host "$(get-date) finished" -ForegroundColor green
    }
    catch {
        write-error ($_ | out-string)
        write-error ($error | out-string)
	}
}

main