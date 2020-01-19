#
[cmdletbinding()]
param(
    [string]$scripts = "",
    [int]$sleepMinutes = 1,
    [string]$detail = $env:detail,
    [int]$timeToLiveMinutes = 60
)

$error.Clear()
$errorActionPreference = "continue"
$scripts = @($scripts.Split(';'))
$nodeName = $env:Fabric_NodeName
$source = $env:Fabric_ServiceName

function main() {
    try {
        write-log "starting"
        $nodeName = set-nodeName -nodeName $nodeName
        if (!$source) { $source = [io.path]::GetFileName($MyInvocation.ScriptName) }

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
            write-verbose ($job | format-list * | out-string)

            if ($job.state -ine "running") {
                write-log -data ($job | format-list * | out-string) -report $job.name

                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    write-log -data "ERROR:$($job | format-list * | out-string)" -report $job.name
                }

                write-log -data ($job.output | ConvertTo-Json) -report $job.name
                remove-job -Id $job.Id -Force  
            }
            else {
                $jobInfo = (receive-job -Id $job.id)
                if ($jobInfo) {
                    write-log -data $jobInfo -report $job.name
                }
            }
            start-sleep -Seconds 1
        }
    }
}

function remove-jobs() {
    write-log "removing jobs"
    try {
        foreach ($job in get-job) {
            write-log "removing job $($job.Name)"
            $job.StopJob()
            Remove-Job $job -Force
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
        start-job -Name $scriptFileName -ArgumentList @($scriptFile, $scriptArgs) -scriptblock { 
            param($scriptFile, $scriptArgs)
            write-host "$scriptFile $scriptArgs"
            invoke-expression -command "$scriptFile $scriptArgs"
        }
    }
}

function set-nodeName($nodeName) {
    if (!$nodeName) {
        $index = $env:COMPUTERNAME.Substring($env:COMPUTERNAME.Length - 6).trimstart('0')
        if (!$index) { $index = "0" }
        $name = "_$($env:COMPUTERNAME.Substring(0, $env:COMPUTERNAME.Length - 6))_"
        $nodeName = "$name$index"
    }

    write-log "using nodename $nodeName"
    return $nodeName
}

function write-log($data, $report) {
    if (!$data) { return }
    $data = "$(get-date):$data"
    $sendReport = ($detail -imatch "true") -and $report
    $level = "Ok"

    if ($data -imatch "error") {
        write-error $data
        $level = "Error"
        $sendReport = $true
    }
    elseif ($data -imatch "warning") {
        write-warning $data
        $level = "Warning"
        $sendReport = $true
    }

    write-host "$level : $sendReport : $report : $data`r`n"

    if ($sendReport) {
        try {
            if (!(get-serviceFabricClusterConnection)) { connect-servicefabriccluster }
            $error.clear()

            if (!$report) { $report = $MyInvocation.ScriptName }
            write-host "Send-ServiceFabricNodeHealthReport 
                -RemoveWhenExpired
                -TimeToLiveSec ($timeToLiveMinutes * 60)
                -NodeName $nodeName 
                -HealthState $level 
                -SourceId $source 
                -HealthProperty $report 
                -Description `"$data`r`n`""
                
            Send-ServiceFabricNodeHealthReport -NodeName $nodeName `
                -RemoveWhenExpired `
                -TimeToLiveSec ($timeToLiveMinutes * 60) `
                -HealthState $level `
                -SourceId $source `
                -HealthProperty $report `
                -Description "$data"
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