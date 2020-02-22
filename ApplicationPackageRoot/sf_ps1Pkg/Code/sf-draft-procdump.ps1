#
# draft
#

param(
    [string]$sysInternalsExe = ($env:sysInternalsExe, "procdump.exe" -ne $null)[0],
    [string]$sysInternalsExeStartCommand = ($env:sysInternalsExeStartCommand, "-accepteula -l -ma" -ne $null)[0],
    [string]$sysInternalsExeStopCommand = ($env:sysInternalsExeStopCommand, "" -ne $null)[0],
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*.*" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [switch]$noExecute = $env:noExecute,
    [string]$processName = ($env:processName, "notepad" -ne $null)[0],
    [switch]$allProcessInstances = ($env:allProcessInstances, $true -ne $null)[0],
    [switch]$requiresAdmin = $env:requiresAdmin
)

write-host "$(get-date) `r`n$psboundparameters"
[net.ServicePointManager]::Expect100Continue = $true
[net.ServicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12

$ErrorActionPreference = "continue"
$error.clear()
$scriptParameters = $PsBoundParameters

function main() {
    try {
        $timer = get-date
        $process = $null
        write-host "$($MyInvocation.ScriptName)`r`n$($psboundparameters | out-string) : $myDescription`r`n" -ForegroundColor Green

        if (!$env:Path.Contains($pwd)) {
            $env:Path += ";$pwd"
            write-host "$(get-date) new path $env:Path" -ForegroundColor Green
        }

        if (!$processName) {
            write-error "`$processName is required"
            return $false
        }

        if (!(check-admin)) { return }
        if (!(download-files)) { return }

        if ($noExecute) {
            write-host "$(get-date) noexecute returning" -ForegroundColor Green
        }

        $wildName = "*$([io.path]::GetFileNameWithoutExtension($processName))*"
        $processes = @{ }

        if ([convert]::ToInt32($processName)) {
            $processes = @(get-process | select Name, Id | ? Id -eq $processName)
        }
        else {
            $processes = @(get-process | select Name, Id | ? Name -ieq $processName)
            if (!$processes) {
                $processes = @(get-process | select Name, Id | ? Name -imatch $processName)
            }
        }

        $startArguments = $sysInternalsExeStartCommand

        switch ($processes.Count) {
            { $_ -eq 1 } { 
                $startArguments += " $($processes[0].Name)"
            }
            { $_ -gt 1 } { 
                if ($allProcessInstances) {
                    write-host "multiple processses. attaching to $($processes.Count) instances"
                    foreach ($process in $processes) {
                        $scriptParameters.processName = $process.Id
                        start-job -Name $process.Id -ArgumentList @($MyInvocation.ScriptName, $scriptParameters) -scriptblock { 
                            param($exe, $startArguments)
                            write-host "start-job:$exe $startArguments"
                            invoke-expression -command "$exe $startArguments"
                        }
                    }

                    while (get-job) {
                        $job = get-job
                        $results = Receive-Job -Job $Job
                        Write-Host ($results | convertto-json)
                        if ($job.State -ine "running") {
                            write-host "$($job.state) $($job.status) $($job | fl * | out-string)"
                            Remove-Job -Job $job -force
                        }
                        start-sleep -Seconds 1
                    }
                }
                else {
                    write-warning "multiple processses. attaching to first only"
                    $startArguments += " $($processes[0].Id)"
                }
            }
            { $_ -lt 1 } { 
                $startArguments += " -w $processName"
            }
        }

        start-command
        wait-command
        stop-command
        copy-files

        write-host "$(get-date) finished" -ForegroundColor Green
        write-host "$(get-date) timer: $(((get-date) - $timer).tostring())" -ForegroundColor Green
    }
    catch {
        write-error "exception:$($_ | fl * | out-string)"
        write-error "$($error | fl * | out-string)`r`n$(get-pscallstack | fl * | out-string)"
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
        write-host "$(get-date) $($error | fl * | out-string)"
        $error.Clear()
        return $true
    }
    return $false
}

function copy-files($source = $outputFilePattern, $destination = $outputFileDestination) {
    if ($destination) {
        write-host "$(get-date) moving files $source to $destination"
        if (!(test-path $destination) -and !(new-item -Path $destination -ItemType Directory)) {
            write-error "$(get-date) unable to create directory $destination"
        }
        else {
            foreach ($item in get-item -path $source) {
                $error.Clear()
                write-host "$(get-date) compress-archive -Path $item -DestinationPath $destination\$([io.path]::GetFileNameWithoutExtension($item)).zip"
                compress-archive -Path $item -DestinationPath "$destination\$([io.path]::GetFileNameWithoutExtension($item)).zip" -Force
                if (!$error) {
                    write-host "$(get-date) removing $item"
                    remove-item $item -Force -Recurse
                }
            }
        }
    }
}

function download-files() {
    $error.Clear()
    if (!(test-path $sysinternalsexe)) {
        write-host "$(get-date) downloading $sysinternalsExe" -ForegroundColor Green
        (new-object net.webclient).DownloadFile("http://live.sysinternals.com/$sysinternalsexe", "$pwd\$sysinternalsexe")
    }
    return check-error
}
function stop-command($exe = $sysInternalsExe, $arguments = $sysInternalsExeStopCommand) {
    if ($sysinternalsExeStopCommand) {
        write-host "$(get-date) stopping $exe $arguments" -ForegroundColor Green
        $process = start-process -PassThru -FilePath $exe -ArgumentList $arguments
        write-host "$(get-date) stopping process info: $($process | fl * | out-string)" -ForegroundColor Green
    }
    else {
        write-host "$(get-date) killing $exe" -ForegroundColor Green
        #stop-process -Id $process.Id -Force
        # procdump wants ctrl-c to detach
        $process.CloseMainWindow()
        
        write-host "$(get-date) killing process info: $($process | fl * | out-string)" -ForegroundColor Green
        if ($allProcessInstances) {
            $wildName = "*$([io.path]::GetFileNameWithoutExtension($exe))*"
            stop-process -name $wildName -Force
            write-host "$(get-date) killing proces name $wildName : $($process | fl * | out-string)" -ForegroundColor Green
        }
    }
}

function start-command($exe = $sysInternalsExe, $arguments = $sysInternalsExeStartCommand) {
    $error.Clear()
    write-host "$(get-date) starting $exe $arguments" -ForegroundColor Green
    $process = start-process -PassThru -FilePath $exe -ArgumentList $arguments
    write-host "$(get-date) starting process info: $($process | fl * | out-string)" -ForegroundColor Green
    if ($error -or !$process -or $process.ExitCode) {
        write-error "$(get-date) $($error | out-string) $($process | out-string)"
        return
    }

}

function wait-command($minutes = $sleepMinutes, $currentTimer = $timer) {
    write-host "$(get-date) sleeping for $sleepMinutes minutes`r`ntimer: $(((get-date) - $currentTimer).tostring())" -ForegroundColor Green
    #start-sleep -Seconds ($sleepMinutes * 60)
    Wait-Process -Id $process.id -Timeout ($sleepMinutes * 60) -ErrorAction SilentlyContinue
    write-host "$(get-date) resuming`r`ntimer: $(((get-date) - $currentTimer).tostring())" -ForegroundColor Green
    write-host "$(get-date) waiting process info: $($process | fl * | out-string)" -ForegroundColor Green

    if (($error -or !$process) -or ($process.ExitCode -and $process.ExitCode -ne 0)) {
        write-error "error:$(get-date) $($error | out-string) $($process | fl * | out-string)"
    }
}

main