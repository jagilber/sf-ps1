###########################
# sf-ps1 netsh network trace
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [string]$outputFile = ($env:outputFile, "$pwd\$env:computername-net.$((get-date).tostring("MMddhhmmss")).etl" -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*net.*.etl" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0]
)

$ErrorActionPreference = "continue"
write-host "$($psboundparameters | fl * | out-string)`r`n" -ForegroundColor green
# include functions
. .\functions.ps1

function main() {
    try{
        do {
            $error.clear()
            $startTimer = get-date
            write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters`r`n"
            if(!(check-admin)) {return}

            # remove existing trace
            stop-command

            # start new trace
            start-command
            check-error
            wait-command

            # stop new trace
            stop-command
            check-error

            # copy trace
            copy-files

            write-host "$(get-date) timer: $(((get-date) - $startTimer).tostring())"
            write-host "$(get-date) finished" -ForegroundColor green
        }
        while ($continuous) 
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
    }
}

function stop-command() {
    write-host "$(get-date) stopping existing trace`r`n" -ForegroundColor green
    netsh trace stop
}

function start-command() {
    write-host "$(get-date) starting trace" -ForegroundColor green
    netsh trace start capture=yes overwrite=yes maxsize=$maxSizeMb traceFile=$outputFile filemode=circular
}

main