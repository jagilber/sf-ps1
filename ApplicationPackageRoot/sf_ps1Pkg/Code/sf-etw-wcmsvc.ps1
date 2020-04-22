###########################
# sf-ps1 etw template script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 5 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*sf_ps1_etw*.etl" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0],
    [string]$sessionName = "sf_ps1_etw_Session",
    [string]$outputFile = ".\sf_ps1_etw.etl",
    [string]$mode = 'Circular',
    [int]$buffSize = 1024,
    [int]$numBuffers = 16,
    [string]$keywords = '0xffffffffffffffff',
    [string[]]$etwProviders = @(
        '{988CE33B-DDE5-44EB-9816-EE156B443FF1}',
        'Microsoft-Windows-Wcmsvc',
        '{0616F7DD-722A-4DF1-B87A-414FA870D8B7}',
        'Microsoft-Windows-DNS-Client'
    )
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = "continue"
write-host "$($psboundparameters | fl * | out-string)`r`n" -ForegroundColor green
$script:commandRunning = $false

function main() {
    try {
        do {
            set-location $psscriptroot
            $error.clear()
            $timer = get-date
            write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters`r`n"
            if (!(check-admin)) { return }

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

            write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
            write-host "$(get-date) finished" -ForegroundColor green
        }
        while ($continuous) 
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
    }
    finally {
        if($script:commandRunning){
            stop-command
        }
    }
}

function copy-files($source = "$pwd\$outputFilePattern", $destination = $outputFileDestination) {
    if ($destination) {
        write-host "$(get-date) moving files $source to $destination"
        if (!(test-path $destination) -and !(new-item -Path $destination -ItemType Directory)) {
            write-error "$(get-date) unable to create directory $destination"
        }
        else {
            move-item -path $source -destination $destination -Force
        }
    }
}

function check-admin() {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (!$isAdmin) {
        write-error "error:restart script as administrator"
        return $false
    }

    return $true
}

function check-error() {
    if ($error) {
        write-error "$(get-date) $($error | fl * | out-string)"
        $error.Clear()
    }
}

function wait-command($minutes = $sleepMinutes) {
    write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
    write-host "$(get-date) sleeping $minutes minutes" -ForegroundColor green
    start-sleep -Seconds ($minutes * 60)
    write-host "$(get-date) resuming" -ForegroundColor green
    $timer = get-date
}

function stop-command() {
    write-host "$(get-date) stopping existing trace`r`n" -ForegroundColor green
    write-host "logman stop $sessionName -ets"
    logman stop $sessionName -ets
    $script:commandRunning = $false
}

function start-command() {
    write-host "$(get-date) starting trace" -ForegroundColor green
    write-host "logman create trace $sessionName -ow -o $outputFile -nb $numBuffers $numBuffers -bs $buffSize -mode $mode -f bincirc -max $maxSizeMb -ets"
    logman create trace $sessionName -ow -o $outputFile -nb $numBuffers $numBuffers -bs $buffSize -mode $mode -f bincirc -max $maxSizeMb -ets
            
    foreach ($etwProvider in $etwProviders) {
        write-host "logman update trace $sessionName -p $etwProvider $keywords 0xff -ets"
        logman update trace $sessionName -p $etwProvider $keywords 0xff -ets
    }
    $script:commandRunning = $true
}

main