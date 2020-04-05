#
[cmdletbinding()]
param(
    [string]$scripts = $env:scripts,
    [int]$sleepSeconds = ($env:sleepSeconds, 1 -ne $null)[0], # todo fix. 
    [string]$detail = $env:detail,
    [string]$runOnNodes = $env:runOnNodes,
    [int]$reportTimeToLiveMinutes = ($env:reportTimeToLiveMinutes, 60 -ne $null)[0],
    [datetime]$scriptStartDateTimeUtc = ($env:scriptStartDateTimeUtc, (get-date).ToUniversalTime() -ne $null)[0],
    [int]$scriptRecurrenceMinutes = ($env:scriptRecurrenceMinutes, 0 -ne $null)[0],
    [switch]$doNotReturn
)

$error.Clear()
$errorActionPreference = "continue"
$global:scriptCommands = @($scripts.Split(';'))
$global:nodes = @($runOnNodes.Split(','))
$nodeName = $env:Fabric_NodeName
$source = $env:Fabric_ServiceName
$global:scriptName = $null
$global:scriptParams = ($psboundparameters | out-string)
$global:sfClientAvailable = $false

function main() {
    if(connect-serviceFabricCluster) { 
        $global:sfClientAvailable = $true
    }
    else {
        Write-Warning "sfclient unavailable"
    }

    try {
        set-location $psscriptroot
        $global:scriptName = [io.path]::getFileName($MyInvocation.ScriptName)
        
       
        write-log "starting $global:ScriptName $global:scriptParams" -report $global:scriptName

        if (!$nodeName) { $nodeName = set-nodeName }
        if (!$source) { $source = [io.path]::GetFileName($MyInvocation.ScriptName) }

        if(@($global:nodes) -and !$global:nodes.Contains($nodeName)) {
            write-log "$nodeName not in list of runOnNodes $runOnNodes`r`nreturning"
            pause-return
        }

        if(!$env:Path.Contains($pwd)) {
            $env:Path += ";$pwd"
            write-host "new path $env:Path" -ForegroundColor Green
        }

        remove-jobs

        if ($scriptStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
            write-log "waiting $totalSeconds seconds for starttime: $scriptStartDateTimeUtc" -report $global:scriptName
            while ($scriptStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
                $totalSeconds = ([datetime]($scriptStartDateTimeUtc.Ticks - (get-date).ToUniversalTime().Ticks)).Second
                Start-Sleep -Seconds $totalSeconds
            }
            write-log "resuming for starttime: $scriptStartDateTimeUtc" -report $global:scriptName
        }

        start-jobs
        wait-jobs

        if($scriptRecurrenceMinutes) {
            $recurrenceStartDateTimeUtc = $scriptStartDateTimeUtc
            while($true) {
                $recurrenceStartDateTimeUtc = $recurrenceStartDateTimeUtc.addMinutes($scriptRecurrenceMinutes)
                if ($recurrenceStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
                    $totalSeconds = ([datetime]($recurrenceStartDateTimeUtc.Ticks - (get-date).ToUniversalTime().Ticks)).Second
                    write-log "waiting $totalSeconds seconds for recurrencetime: $scriptStartDateTimeUtc" -report $global:scriptName
                    Start-Sleep -Seconds $totalSeconds
                    write-log "resuming for recurrence: $scriptStartDateTimeUtc" -report $global:scriptName
                }
                
                write-log "starting jobs for recurrence: $scriptStartDateTimeUtc" -report $global:scriptName
                start-jobs
                wait-jobs
            }
        }

        pause-return
    }
    catch {
        write-log "error: $($_ | out-string)" -report $global:scriptName
        write-error ($error | out-string)
    }
    finally {
        remove-jobs
        write-log "finished: " -report $global:scriptName
        exit
    }
}

function remove-jobs() {
    try {
        foreach ($job in get-job) {
            write-log "removing job $($job.Name)" -report $global:scriptName
            write-log $job -report $global:scriptName
            $job.StopJob()
            Remove-Job $job -Force
        }
    }
    catch {
        write-log "error:$($Error | out-string)"
        $error.Clear()
    }
}

function pause-return(){
    if($doNotReturn) {
        write-log "pausing: $scriptStartDateTimeUtc" -report $global:scriptName
        while($true) {
            start-sleep -seconds $sleepSeconds
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

function start-jobs() {
    write-log "starting jobs: $scriptStartDateTimeUtc" -report $global:scriptName

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
        write-log "starting job $($job.Name)  $scriptFile $scriptArgs" -report $global:scriptName
        write-log $job -report $global:scriptName
        start-job -Name $scriptFileName -ArgumentList @($scriptFile, $scriptArgs) -scriptblock { 
            param($scriptFile, $scriptArgs)
            write-host "start-job:$scriptFile $scriptArgs"
            invoke-expression -command "$scriptFile $scriptArgs"
        }
    }
}

function wait-jobs() {
    write-log "monitoring jobs: $scriptStartDateTimeUtc" -report $global:scriptName
    while (get-job) {
        foreach ($job in get-job) {
            $jobInfo = (receive-job -Id $job.id)
            if ($jobInfo) {
                write-log -data $jobInfo -report $job.name
            }
            else {
                write-log -data $job -report $job.name
            }

            if ($job.state -ine "running") {
                write-log -data $job

                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    write-log -data $job -report $job.name
                }

                write-log -data $job -report $job.name
                remove-job -Id $job.Id -Force  
            }
#            else {
#                $jobInfo = (receive-job -Id $job.id)
#                if ($jobInfo) {
#                    write-log -data $jobInfo -report $job.name
#                }
#            }

            start-sleep -Seconds $sleepSeconds
        }
    }

    write-log "finished jobs: $scriptStartDateTimeUtc" -report $global:scriptName
}

function write-log($data, $report) {
    if (!$data) { return }
    [string]$stringData = ""
    $sendReport = ($detail -imatch "true") -and $report
    $level = "Ok"
    $jobName = $null

    if($data.GetType().Name -eq "PSRemotingJob") {
        $jobName = $data.Name
        foreach($job in $data.childjobs){
            if($job.Information) {
                $stringData += (@($job.Information.ReadAll()) -join "`r`n")
            }
            if($job.Output) {
                $stringData += (@($job.Output.ReadAll()) -join "`r`n")
            }
            if($job.Warning) {
                write-warning (@($job.Warning.ReadAll()) -join "`r`n")
                $level = "Warning"
                $sendReport = $true
                $stringData += (@($job.Warning.ReadAll()) -join "`r`n")
                $stringData += ($job | fl * | out-string)
            }
            if($job.Error) {
                write-error (@($job.Error.ReadAll()) -join "`r`n")
                $level = "Error"
                $sendReport = $true
                $stringData += (@($job.Error.ReadAll()) -join "`r`n")
                $stringData += ($job | fl * | out-string)
            }

            if($stringData.Trim().Length -gt 0) {
                $stringData += "`r`nname: $($data.Name) state: $($job.State) $($job.Status) $($job.PSBeginTime)`r`n"
            }
            else{
                return
            }
        }
    }
    else {
        $stringData = "$(get-date):$($data | fl * | out-string)"
    }

    $stringData = "$(get-date) level: $level sendreport: $sendReport report: $report data:`r`n$stringData`r`n"
    write-host $stringData
    if($global:sfClientAvailable) {
        try {
            out-file -FilePath "..\log\$global:scriptName.log" -InputObject $stringData -Append -errorAction continue
        }
        catch {
            write-warning "unable to save to log file: $($_)"  
		}
    }

    if ($sendReport -and $global:sfClientAvailable) {
        try {
            if (!(get-serviceFabricClusterConnection)) { connect-servicefabriccluster }
            $error.clear()

            if (!$report) { $report = ($jobName, $global:scriptName -ne $null)[0] }
            write-host "$(get-date) Send-ServiceFabricNodeHealthReport 
                -RemoveWhenExpired
                -TimeToLiveSec $($reportTimeToLiveMinutes * 60)
                -NodeName $nodeName 
                -HealthState $level 
                -SourceId $source 
                -HealthProperty $report 
                -Description `"$stringData`r`n`""
                
            Send-ServiceFabricNodeHealthReport -NodeName $nodeName `
                -RemoveWhenExpired `
                -TimeToLiveSec ($reportTimeToLiveMinutes * 60) `
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


# execute script
main
#