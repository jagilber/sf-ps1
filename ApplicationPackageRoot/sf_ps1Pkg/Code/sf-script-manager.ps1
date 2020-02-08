#
[cmdletbinding()]
param(
    [string]$scripts = $env:scripts,
    [int]$sleepSeconds = ($env:sleepSeconds, 1 -ne $null)[0],
    [string]$detail = $env:detail,
    [int]$timeToLiveMinutes = ($env:timeToLiveMinutes, 60 -ne $null)[0],
    [datetime]$scriptStartDateTimeUtc = $env:scriptStartDateTimeUtc,
    [int]$scriptReccurrenceMinutes = $env:scriptReccurrenceMinutes
)

$error.Clear()
$errorActionPreference = "continue"
$global:scriptCommands = @($scripts.Split(';'))
$nodeName = $env:Fabric_NodeName
$source = $env:Fabric_ServiceName

function main() {
    try {
        write-log "starting"
        if (!$nodeName) { $nodeName = set-nodeName }
        if (!$source) { $source = [io.path]::GetFileName($MyInvocation.ScriptName) }

        connect-serviceFabricCluster
        remove-jobs

        if ($scriptStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
            $totalSeconds = ([datetime]($scriptStartDateTimeUtc.Ticks - (get-date).ToUniversalTime().Ticks)).Second
            write-log "waiting $totalSeconds seconds for starttime: $scriptStartDateTimeUtc"
            Start-Sleep -Seconds $totalSeconds
            write-log "resuming for starttime: $scriptStartDateTimeUtc"
        }

        start-jobs
        monitor-jobs

        if($scriptReccurrenceMinutes) {
            $recurrenceStartDateTimeUtc = $scriptStartDateTimeUtc
            while($true) {
                $recurrenceStartDateTimeUtc = $recurrenceStartDateTimeUtc.addMinutes($scriptReccurrenceMinutes)
                if ($reccurenceStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
                    $totalSeconds = ([datetime]($recurrenceStartDateTimeUtc.Ticks - (get-date).ToUniversalTime().Ticks)).Second
                    write-log "waiting $totalSeconds seconds for recurrencetime: $scriptStartDateTimeUtc"
                    Start-Sleep -Seconds $totalSeconds
                    write-log "resuming for recurrence: $scriptStartDateTimeUtc"
                }

                start-jobs
                monitor-jobs
            }
        }
    }
    catch {
        write-log "error: $($_ | out-string)"
        write-error ($error | out-string)
    }
    finally {
        remove-jobs
        write-log "finished"
        exit
    }
}

function monitor-jobs() {
    write-log -data "monitoring jobs"
    while (get-job) {
        foreach ($job in get-job) {
            write-log -data $job

            if ($job.state -ine "running") {
                write-log -data $job

                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    write-log -data $job -report $job.name
                }

                write-log -data $job -report $job.name
                remove-job -Id $job.Id -Force  
            }
            else {
                $jobInfo = (receive-job -Id $job.id)
                if ($jobInfo) {
                    write-log -data $jobInfo -report $job.name
                }
            }

            start-sleep -Seconds $sleepSeconds
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

    if(!$global:scriptCommands) {
        write-error "no scripts to execute. exiting"
        return
    }

    foreach ($script in $global:scriptCommands) {
        write-log "executing script: $($script)"
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
            #start-process -filePath "powershell.exe" -ArgumentList "$scriptFile $scriptArgs" -Verb RunAs -wait
        }
    }
}

function set-nodeName($nodeName = $env:COMPUTERNAME) {
    # base 36 -> base 10
    $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    [long]$decimalNumber=0
    $position=0
    $base36Number = $nodeName.substring($nodeName.Length - 6).trimStart('0')
    $name = "_$($nodeName.substring(0, $nodeName.Length - 6))_"

    if (!$base36Number) { $base36Number = "0" }
    $inputArray = $base36Number.toLower().toCharArray()
    [array]::reverse($inputArray)

    foreach ($character in $inputArray) {
        $decimalNumber += $alphabet.IndexOf($character) * [long][Math]::Pow(36, $position)
        $position++
    }
    
    $nodeName = "$name$decimalNumber"
    write-log "using nodename $nodeName"
    return $nodeName
}

function write-log($data, $report) {
    if (!$data) { return }
    [string]$stringData = ""
    $sendReport = ($detail -imatch "true") -and $report
    $level = "Ok"

    if($data.GetType().Name -eq "PSRemotingJob") {
        foreach($job in $data.childjobs){
            $stringData += "name: $($data.Name) state: $($job.State) status: $($job.Status)"

            if($job.Output) {
                $level = "Ok"
                $stringData += (@($job.Output.ReadAll()) -join "`r`n")
            }
            if($job.Warning) {
                write-warning (@($job.Warning.ReadAll()) -join "`r`n")
                $level = "Warning"
                $sendReport = $true
                $stringData += (@($job.Warning.ReadAll()) -join "`r`n")
            }
            if($job.Error) {
                write-error (@($job.Error.ReadAll()) -join "`r`n")
                $level = "Error"
                $sendReport = $true
                $stringData += (@($job.Error.ReadAll()) -join "`r`n")
            }
        }
    }
    else {
        $stringData = "$(get-date):$($data | fl * | out-string)"
    }

    write-host "$level : $sendReport : $report : $stringData`r`n"

    if ($sendReport) {
        try {
            if (!(get-serviceFabricClusterConnection)) { connect-servicefabriccluster }
            $error.clear()

            if (!$report) { $report = $MyInvocation.ScriptName }
            write-host "Send-ServiceFabricNodeHealthReport 
                -RemoveWhenExpired
                -TimeToLiveSec $($timeToLiveMinutes * 60)
                -NodeName $nodeName 
                -HealthState $level 
                -SourceId $source 
                -HealthProperty $report 
                -Description `"$stringData`r`n`""
                
            Send-ServiceFabricNodeHealthReport -NodeName $nodeName `
                -RemoveWhenExpired `
                -TimeToLiveSec ($timeToLiveMinutes * 60) `
                -HealthState $level `
                -SourceId $source `
                -HealthProperty $report `
                -Description "$stringData"
        }
        catch {
            write-host "error sending report: $(($error | out-string))"
            write-error ($error | out-string)
            $error.Clear()
        }
    }
}

write-log ($psboundparameters | out-string)
# execute script
main
#