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
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0],
    [string]$csvFile = ($env:csvFile, "$pwd\net.csv" -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try{
        $session = "nettrace"        
        $timer = get-date
        write-output "$($MyInvocation.ScriptName)`r`n$psboundparameters : $myDescription`r`n"

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

        if(!$isAdmin){
            write-output "error:restart script as administrator"
            return
        }

        write-output "$(get-date) stopping existing trace`r`n"
        write-output (netsh trace stop)

        write-output "$(get-date) starting trace`r`n"
        write-output (netsh trace start capture=yes overwrite=yes maxsize=$maxSizeMb tracefile=$traceFile filemode=circular)

        write-output "$(get-date) sleeping $sleepMinutes minutes`r`n"
        start-sleep -Seconds ($sleepMinutes * 60)

        write-output "$(get-date) stopping trace`r`n"
        write-output (netsh trace stop)

        if ($error) {
            write-output "ERROR:$myErrorDescription`r`n"
            write-output "$($error | out-string)`r`n"
        }

        write-output "copying files`r`n"
        copy net.* ..\log
        
        write-output "$(get-date) timer: $(((get-date) - $timer).tostring())`r`n"
        write-output "$(get-date) finished`r`n"
        
    }
    catch {
        write-output ($_ | out-string)
        write-output ($error | out-string)
        
	}
}

main