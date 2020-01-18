#
[cmdletbinding()]
param(
    [string[]]$scripts = @(),
    [int]$sleepMinutes = 1,
    [string]$detail = $env:detail
)


$errorActionPreference = "continue"
$global:joboutputs = @{ }
$global:fail = 0
$global:success = 0
$scripts = @($scripts.Split(','))
$nodeName = $env:Fabric_NodeName
$source = $env:Fabric_ServiceName
$error.Clear()

function main() {
    try {
        write-log "starting"
        $nodeName = set-nodeName -nodeName $nodeName
        if(!$source) { $source = [io.path]::GetFileName($MyInvocation.ScriptName) }

        connect-serviceFabricCluster
        remove-jobs
        start-jobs
        monitor-jobs
    }
    catch {
        write-log "error:($error | out-string)"
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
                write-log -data ($job | fl * | out-string) -report $true

                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job | ConvertTo-Json))
                    $global:fail++
                }
                else {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job.output | ConvertTo-Json))
                    $global:success++
                }

                write-log -data ($job.output | ConvertTo-Json) -report $true
                remove-job -Id $job.Id -Force  
            }
            else {
                $jobInfo = (receive-job -Id $job.id)
                if($jobInfo){
                    write-log -data $jobInfo -report $true
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
        $scriptArgs = $script.substring($argIndex).trim()
        $scriptFileName = [io.path]::GetFileName($scriptFile)
        write-log "checking file:$scriptFile`r`n`targs:$scriptArgs"

        if ($scriptFile.tolower().startswith("http")) {
            [net.servicePointManager]::Expect100Continue = $true;
            [net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
            write-log "downloading $scriptFile"
            $downloadedFile = "$env:temp\$scriptFileName"
            (new-object net.webclient).DownloadFile($scriptFile, $downloadedFile)
            $scriptFile = $downloadedFile
        }
        elseif (!(test-path $scriptFile)) {
            write-log "error:$scriptFile does not exist"
            continue
        }

        $scriptFile = resolve-path $scriptFile

        write-log "starting $scriptFile $scriptArgs"
        start-job -Name $scriptFile -ArgumentList @($scriptFile, $scriptArgs) -scriptblock { 
            param($scriptFile, $scriptArgs)
            write-host "$scriptFile $scriptArgs"
            invoke-expression -command "$scriptFile $scriptArgs"
        }
    }
}

function set-nodeName($nodeName){
    if(!$nodeName) {
        $index = $env:COMPUTERNAME.Substring($env:COMPUTERNAME.Length - 6).trimstart('0')
        if(!$index) { $index = "0" }
        $name = "_$($env:COMPUTERNAME.Substring(0, $env:COMPUTERNAME.Length - 6))_"
        $nodeName = "$name$index"
    }

    write-log "using nodename $nodeName"
    return $nodeName
}

function write-log($data, $report = $false) {
    if(!$data) { return }
    $data = "$(get-date):$data"
    $sendReport = ($detail -imatch "true") -and $report
    $level = "Ok"

    if ($level -imatch "error") {
        write-error $data
        $level = "Error"
        $sendReport = $true
    }
    elseif ($level -imatch "warning") {
        write-warning $data
        $level = "Warning"
        $sendReport = $true
    }

    write-host "$level : $sendReport : $report : $data`r`n"

    if ($sendReport) {
        try {
            if (!(get-serviceFabricClusterConnection)) { connect-servicefabriccluster }
            $error.clear()
            write-host "Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId $source -HealthProperty $($MyInvocation.MyCommand.Name) -Description `"$data`r`n`""
            Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId $source -HealthProperty ($MyInvocation.MyCommand.Name) -Description "$data"
        }
        catch {
            write-host "error sending report: $(($error | out-string))"
            write-error ($error | out-string)
            $error.Clear()
        }
    }
}

# execute script
main
#