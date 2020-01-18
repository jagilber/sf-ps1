#
[cmdletbinding()]
param(
    [string[]]$scripts = @(),
    [int]$sleepMinutes = 1,
    [string]$nodeName = $env:Fabric_NodeName,
    [string]$source = $env:Fabric_ServiceName,
    [string]$detail = $env:detail
)


$errorActionPreference = "silentlycontinue"
$global:joboutputs = @{}
$global:fail = 0
$global:success = 0
$scripts = @($scripts.Split(','))

function main() {
    try {
        write-log "starting"
        remove-jobs
        start-jobs
        monitor-jobs
    }
    catch {
        write-error ($error | out-string)
    }
    finally {
        remove-jobs
        write-log "finished"
    }
}

function monitor-jobs() {
    write-log "monitoring jobs"

    while (get-job) {
        foreach ($job in get-job) {
            write-verbose ($job | fl * | out-string)

            if ($job.state -ine "running") {
                write-log ($job | fl * | out-string) -report $true

                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job | ConvertTo-Json))
                    $global:fail++
                }
                else {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job.output | ConvertTo-Json))
                    $global:success++
                }

                write-log ($job.output | ConvertTo-Json) -report $true
                $job.output
                Remove-Job -Id $job.Id -Force  
            }
            else {
                $jobInfo = Receive-Job -Job $job
                
                if ($jobInfo) {
                    write-log ($jobInfo | fl * | out-string) -report $true
                }
            }

            start-sleep -Seconds 1
        }
    }
}

function remove-jobs() {
    write-log "removing jobs"
    try {
        if (@(get-job).Count -gt 0) {
            foreach ($job in get-job) {
                write-log "removing job $($job.Name)"
                $job.StopJob()
                Remove-Job $job -Force
            }
        }
    }
    catch {
        write-log "error:$($Error | out-string)"
        $error.Clear()
    }
}

function start-jobs() {
    write-log "start jobs scripts count: $($scripts.Count)"
    foreach ($script in $scripts) {
        $argIndex = $script.LastIndexOf('.ps1') + 4
        $scriptFile = $script.substring(0, $argIndex)
        $scriptArgs = $script.substring($argIndex + 1)
        $scriptFileName = [io.path]::GetFileName($scriptFile)
        write-log "checking file:$scriptFile`r`n`targs:$scriptArgs"

        if($scriptFile.tolower().startswith("http")) {
            [net.servicePointManager]::Expect100Continue = $true;
            [net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
            write-log "downloading $scriptFile"
            $downloadedFile = "$env:temp\$scriptFileName"
            (new-object net.webclient).DownloadFile($scriptFile, $downloadedFile)
            $scriptFile = $downloadedFile
        }
        elseif(!(test-path $scriptFile)) {
            write-log "error:$scriptFile does not exist"
            continue
        }

        $scriptFile = resolve-path $scriptFile

        write-log "starting $scriptFile $scriptArgs"
        start-job -Name $scriptFile -ArgumentList @($scriptFile, $scriptArgs) -scriptblock { 
            param($scriptFile,$scriptArgs)
            write-output "$scriptFile $scriptArgs"
            write-output (invoke-expression -command "$scriptFile $scriptArgs")
        }
    }
}

function write-log($data, $report = $false) {
    $data = "$(get-date):$data"
    $sendReport = ($detail -imatch "true") -and $report
    $level = "OK"

    if($level -imatch "error") {
        write-error $data
        $level = "Error"
        $sendReport = $true
    }
    elseif($level -imatch "warning") {
        Write-Warning $data
        $level = "Warning"
        $sendReport = $true
    }

    if($sendReport){
        $error.clear()
        write-host "Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId $source -HealthProperty $($MyInvocation.MyCommand.Name) -Description `"$data`r`n`""
        $result = Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId $source -HealthProperty ($MyInvocation.MyCommand.Name) -Description "$data"
       
        if ($error -or $result) { 
            write-host ($result | out-string)
            write-host ($error | out-string)
            $error.Clear()
        }
    }

    write-host "$data`r`n"
}

# execute script
main
#