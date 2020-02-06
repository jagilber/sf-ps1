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
        $msg = "$($MyInvocation.ScriptName)`r`n$psboundparameters : $myDescription`r`n"
        write-output $msg

        $msg = netsh trace start capture=yes overwrite=yes maxsize=$maxSizeMb tracefile=$traceFile filemode=circular
        write-output $msg

        start-sleep -Seconds ($sleepMinutes * 60)
        $msg += netsh trace stop
        write-output $msg

        if ($error) {
            $msg += "ERROR:$myErrorDescription`r`n"
            $msg += "$($error | out-string)`r`n"
        }

        $msg += "copying files"
        copy net.* ..\log

        $msg += "$(get-date) timer: $(((get-date) - $timer).tostring())"
        write-output $msg
    }
    catch {
        $msg += ($_ | out-string)
        $msg += ($error | out-string)
        write-output $msg
	}

}

main