###########################
# sf-ps1 wpr windows performance recorder
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [string]$outputFile = ($env:outputFile, "$env:computername-wpr.$((get-date).tostring("MMddhhmmss")).etl" -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*wpr.*.etl*" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0]
)

$ErrorActionPreference = "continue"
write-host "$($psboundparameters | fl * | out-string)`r`n" -ForegroundColor green

function main() {
    try{
        do {
            set-location $psscriptroot
            $error.clear()
            $timer = get-date
            write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters`r`n"
            if(!(check-admin)) {return}

            # remove existing trace
            stop-command
            check-error

            # start new trace
            start-command
            check-error
            wait-command
            $timer = get-date

            # stop new trace
            stop-command
            check-error

            # copy trace
            copy-files -source

            write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
        }
        while ($continuous) 
        write-host "$(get-date) finished" -ForegroundColor green
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
    }
    finally {
        # stop new trace
        stop-command
        check-error
    }

}

function check-admin() {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if(!$isAdmin){
        write-error "error:restart script as administrator"
        return $false
    }

    return $true
}

function check-error() {
    if ($error) {
        write-error "$(get-date) $($error | fl * | out-string)"
        write-host "$(get-date) $($error | fl * | out-string)"
        $error.Clear()
        return $true
    }
    return $false
}

function copy-files($source = $outputFilePattern, $destination = $outputFileDestination) {
    if($destination) {
        write-host "$(get-date) moving files $source to $destination"
        if(!(test-path $destination) -and !(new-item -Path $destination -ItemType Directory)) {
            write-error "$(get-date) unable to create directory $destination"
        }
        else {
            foreach($item in get-item -path $source) {
                $error.Clear()
                write-host "$(get-date) compress-archive -Path $item -DestinationPath $destination\$([io.path]::GetFileNameWithoutExtension($item)).zip"
                compress-archive -Path $item -DestinationPath "$destination\$([io.path]::GetFileNameWithoutExtension($item)).zip" -Force
                if(!$error) {
                    write-host "$(get-date) removing $item"
                    remove-item $item -Force -Recurse
                }
            }
        }
    }
}

function stop-command() {
    write-host "$(get-date) stopping existing trace`r`n" -ForegroundColor green
    #high cpu
    write-host "$(get-date) stopbefore:wpr -status : isRunning: $(![regex]::IsMatch((wpr -status),'(WPR is not recording)'))`r`n$(wpr -status)"
    if(!([regex]::IsMatch((wpr -status),"(WPR is not recording)"))) {
        $error.Clear()
        write-host "wpr.exe -stop $outputfile $([io.path]::getfilenamewithoutextension($MyInvocation.ScriptName))"
        wpr.exe -stop $outputfile ([io.path]::getFileNameWithoutExtension($MyInvocation.ScriptName))
        $error.Clear()
    }
    write-host "$(get-date) stopafter:wpr -status : isRunning: $(![regex]::IsMatch((wpr -status),'(WPR is not recording)'))`r`n$(wpr -status)"
}

function start-command() {
    write-host "$(get-date) starting trace" -ForegroundColor green
    #high cpu
    write-host "$(get-date) startbefore:wpr -status : isRunning: $(![regex]::IsMatch((wpr -status),'(WPR is not recording)'))`r`n$(wpr -status)"

    write-host "wpr.exe -start CPU -start DiskIO -start FileIO -start Network -start Handle -start HTMLActivity -start HTMLResponsiveness -start DotNET -filemode -recordtempto $pwd"
    wpr.exe -start CPU -start DiskIO -start FileIO -start Network -start Handle -start HTMLActivity -start HTMLResponsiveness -start DotNET -filemode -recordtempto $pwd
    write-host "$(get-date) startafter:wpr -status : isRunning: $(![regex]::IsMatch((wpr -status),'(WPR is not recording)'))`r`n$(wpr -status)"
}

function wait-command($minutes = $sleepMinutes, $currentTimer = $timer) {
    write-host "$(get-date) timer: $(((get-date) - $currentTimer).tostring())"
    write-host "$(get-date) sleeping $minutes minutes" -ForegroundColor green
    start-sleep -Seconds ($minutes * 60)
    write-host "$(get-date) resuming" -ForegroundColor green
    write-host "$(get-date) timer: $(((get-date) - $currentTimer).tostring())"
}

main