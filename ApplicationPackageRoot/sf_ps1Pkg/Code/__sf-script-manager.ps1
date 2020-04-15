# script to manage other scripts and output to node health events
[cmdletbinding()]
param(
    [string]$scripts = $env:scripts,
    [int]$sleepSeconds = ($env:sleepSeconds, 1 -ne $null)[0], # todo fix. 
    [string]$detail = $env:detail,
    [string]$runOnNodes = $env:runOnNodes,
    [int]$reportTimeToLiveMinutes = ($env:reportTimeToLiveMinutes, 60 -ne $null)[0],
    [datetime]$scriptStartDateTimeUtc = ($env:scriptStartDateTimeUtc, (get-date).ToUniversalTime() -ne $null)[0],
    [int]$scriptRecurrenceMinutes = ($env:scriptRecurrenceMinutes, 0 -ne $null)[0],
    [switch]$doNotReturn,
    [string]$logDirectory = '..\log',
    [int]$recycleLimitMB = 500
)

$PSModuleAutoLoadingPreference = 2
$error.Clear()
$errorActionPreference = "continue"
$global:scriptCommands = @($scripts.Split(';'))
$global:nodes = @($runOnNodes.Split(','))
$nodeName = $env:Fabric_NodeName
$source = $env:Fabric_ServiceName
$global:scriptName = $null
$global:scriptParams = ($psboundparameters | out-string)
$global:sfClientAvailable = $false
$global:logStream = $null
$global:logTimer = [timers.timer]::new()
$global:datedLogFile = $null
$global:ProcessInfo = $null

function main() {
    if (connect-serviceFabricCluster) { 
        $global:sfClientAvailable = $true
    }
    else {
        Write-Warning "sfclient unavailable"
    }

    try {
        set-location $psscriptroot
        $global:scriptName = [io.path]::getFileName($MyInvocation.ScriptName)

        write-log "starting $global:ScriptName $global:scriptParams" -report $global:scriptName | out-null

        if (!$nodeName) { $nodeName = set-nodeName }
        if (!$source) { $source = [io.path]::GetFileName($MyInvocation.ScriptName) }

        if (@($global:nodes) -and !$global:nodes.Contains($nodeName)) {
            write-log "$nodeName not in list of runOnNodes $runOnNodes`r`nreturning" | out-null
            pause-return
        }

        if (!$env:Path.Contains($pwd)) {
            $env:Path += ";$pwd"
            write-output "new path $env:Path" -ForegroundColor Green
        }

        remove-jobs

        if ($scriptStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
            write-log "waiting $totalSeconds seconds for starttime: $scriptStartDateTimeUtc" -report $global:scriptName | out-null
            while ($scriptStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
                $totalSeconds = ([datetime]($scriptStartDateTimeUtc.Ticks - (get-date).ToUniversalTime().Ticks)).Second
                Start-Sleep -Seconds $totalSeconds
            }
            write-log "resuming for starttime: $scriptStartDateTimeUtc" -report $global:scriptName | out-null
        }

        while ($true) {
            # todo dont restart jobs not running after first iteration (run-once jobs)
            if (!(start-jobs)) {
                return 1
            }
            
            get-wmiProcessInfo $true

            if (is-overLimit) {
                return 1
            }

            monitor-jobs

            if(!@(get-jobs).count -gt 0){
                # No jobs
                break
            }

            # over MB Limit, restart jobs
            remove-jobs
            # mitigate mem issues
            $before = [System.GC]::GetTotalMemory($false)
            $after = [System.GC]::GetTotalMemory($true)
            write-log "running gc clean: $(get-date) before: $($before) after: $($after)" -report $global:scriptName | Out-Null
        }

        if ($scriptRecurrenceMinutes) {
            $recurrenceStartDateTimeUtc = $scriptStartDateTimeUtc
            while ($true) {
                $recurrenceStartDateTimeUtc = $recurrenceStartDateTimeUtc.addMinutes($scriptRecurrenceMinutes)
                if ($recurrenceStartDateTimeUtc.Ticks -gt (get-date).ToUniversalTime().Ticks) {
                    $totalSeconds = ([datetime]($recurrenceStartDateTimeUtc.Ticks - (get-date).ToUniversalTime().Ticks)).Second
                    write-log "waiting $totalSeconds seconds for recurrencetime: $scriptStartDateTimeUtc" -report $global:scriptName | out-null
                    Start-Sleep -Seconds $totalSeconds
                    write-log "resuming for recurrence: $scriptStartDateTimeUtc" -report $global:scriptName | out-null
                }
                
                write-log "starting jobs for recurrence: $scriptStartDateTimeUtc" -report $global:scriptName | out-null
                start-jobs
                monitor-jobs
            }
        }

        pause-return
    }
    catch {
        write-log "error: $($_ | out-string)" -report $global:scriptName | out-null
        write-error ($error | out-string)
    }
    finally {
        remove-jobs
        write-log "finished: " -report $global:scriptName | out-null
        exit
    }
}

function get-wmiProcessInfo([bool]$reset = $false) {
    # not all os / ps support get-process parent.id so use wmi parentprocessid

    if($reset){
        $global:ProcessInfo = $null
    }
    
    if (!$global:ProcessInfo) {
        if ($PSVersionTable.PSEdition -ieq 'core') {
            $global:ProcessInfo = (get-cimInstance -Class Win32_Process -Namespace root\cimv2)
        }
        else {
            $global:ProcessInfo = (get-wmiobject -Class Win32_Process -Namespace root\cimv2)
        }
    }
    
    $filteredResults = $global:ProcessInfo | where-object { ($_.parentProcessId -eq $pid) -or ($_.processId -eq $pid) }
    $results = $filteredResults | select CommandLine, CreationDate, Handle, WS, ProcessId, UserModeTime, KernelModeTime| out-string

    return $results
}

function is-overLimit() {
    if ((get-process -id $pid | select WS).WS -gt ($recycleLimitMB * 1000000)) {
        write-log "error: memory over working set" -report $global:scriptName | out-null
        return $true
    }

    return $false
}
function remove-jobs() {
    try {
        foreach ($job in get-job) {
            write-log "removing job $($job.Name)" -report $global:scriptName | out-null
            write-log $job -report $global:scriptName | out-null
            $job.StopJob()
            Remove-Job $job -Force
        }
    }
    catch {
        write-log "error:$($Error | out-string)" | out-null
        $error.Clear()
    }
}

function pause-return() {
    if ($doNotReturn) {
        write-log "pausing: $scriptStartDateTimeUtc" -report $global:scriptName | out-null
        while ($true) {
            start-sleep -seconds $sleepSeconds
        }
    }
}

function set-nodeName($nodeName = $env:COMPUTERNAME) {
    # base 36 -> base 10
    $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    [long]$decimalNumber = 0
    $position = 0
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
    write-log "using nodename $nodeName" | out-null
    return $nodeName
}

function start-jobs() {
    write-log "starting jobs: $scriptStartDateTimeUtc" -report $global:scriptName | out-null

    if (!$global:scriptCommands) {
        write-error "no scripts to execute. exiting"
        return $false
    }

    foreach ($script in $global:scriptCommands) {
        write-log "executing script: $($script)" | out-null
        $argIndex = $script.LastIndexOf('.ps1') + 4
        $scriptFile = $script.substring(0, $argIndex)
        $scriptArgs = $script.substring($argIndex).trim()
        $scriptFileName = [io.path]::GetFileName($scriptFile)
        write-log "checking file:$scriptFile`r`n`targs:$scriptArgs" | out-null

        if ($scriptFile.tolower().startswith("http")) {
            [net.servicePointManager]::Expect100Continue = $true;
            [net.servicePointManager]::SecurityProtocol = [net.securityProtocolType]::Tls12;
            write-log "downloading $scriptFile" | out-null
            $downloadedFile = "$env:temp\$scriptFileName"
            (new-object net.webclient).DownloadFile($scriptFile, $downloadedFile)
            $scriptFile = $downloadedFile
        }
        elseif (!(test-path $scriptFile)) {
            write-log "error:$scriptFile does not exist" | out-null
            continue
        }

        $scriptFile = resolve-path $scriptFile
        write-log "starting job $($job.Name)  $scriptFile $scriptArgs" -report $global:scriptName | out-null
        write-log $job -report $global:scriptName | out-null
        start-job -Name $scriptFileName -ArgumentList @($scriptFile, $scriptArgs) -scriptblock { 
            param($scriptFile, $scriptArgs)
            write-output "start-job:$scriptFile $scriptArgs"
            invoke-expression -command "$scriptFile $scriptArgs"
        }
    }
}

function monitor-jobs() {
    write-log "monitoring jobs: $(get-date) 
        gc:$([System.GC]::GetTotalMemory($false)) 
        ws: $((get-process -id $pid | select WS).WS|out-string) 
        $(get-process -Id $pid | out-string)" -report $global:scriptName | out-null

    $count = 0
    while (@(get-job).Count -gt 0 -and !(is-overLimit)) {
        # not working in ps 5.1

        if(++$count % 60 -eq 0){
            write-log -data (get-wmiProcessInfo $true) -report $global:scriptName | out-null
            $count = 0
        }

        foreach ($job in get-job) {
            $jobInfo = (receive-job -Id $job.id)
            if ($jobInfo) {
                write-log -data $jobInfo -report $job.name | out-null
            }
            else {
                write-log -data $job -report $job.name | out-null
            }

            if ($job.state -ine "running") {
                write-log -data $job | out-null

                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    write-log -data $job -report $job.name | out-null
                }

                write-log -data $job -report $job.name | out-null
                remove-job -Id $job.Id -Force  
            }

            start-sleep -Seconds $sleepSeconds
        }
    }

    write-log "finished jobs: $scriptStartDateTimeUtc" -report $global:scriptName | out-null
}

function write-log($data, $report) {
    if (!$data) { return }
    [string]$stringData = ""
    $sendReport = ($detail -imatch "true") -and $report
    $level = "Ok"
    $jobName = $null

    if ($data.GetType().Name -eq "PSRemotingJob") {
        $jobName = $data.Name
        foreach ($job in $data.childjobs) {
            if ($job.Error) {
                $errorData = (@($job.Error.ReadAll()) -join "`r`n").toString().trim()
                $job.Error.Clear()

                if ($errorData) {
                    $stringData = "$errorData`r`$($job | fl * | out-string)`r`n$stringData"
                    write-error (@($job.Error.ReadAll()) -join "`r`n")
                    $level = "Error"
                    $sendReport = $true
                }
            }
            if ($job.Warning) {
                $warningData = (@($job.Warning.ReadAll()) -join "`r`n").toString().trim()
                $job.Warning.Clear()

                if ($warningData) {
                    $stringData = "$warningData`r`$($job | fl * | out-string)`r`n$stringData"
                    write-warning (@($job.Warning.ReadAll()) -join "`r`n")
                    $level = "Warning"
                    $sendReport = $true
                }
            }
            if ($job.Progress) {
                write-verbose (@($job.Progress.ReadAll()) -join "`r`n")
                $job.Progress.Clear()
            }
            if ($job.Information) {
                $stringData += (@($job.Information.ReadAll()) -join "`r`n")
                $job.Information.Clear()
            }
            if ($job.Output) {
                $stringData += (@($job.Output.ReadAll()) -join "`r`n")
                $job.Output.Clear()
            }

            if ($stringData.Trim().Length -gt 0) {
                $stringData += "`r`nname: $($data.Name) state: $($job.State) $($job.Status) $($job.PSBeginTime)`r`n"
            }
            else {
                return
            }
        }
    }
    else {
        $stringData = "$(get-date):$($data | fl * | out-string)"
    }

    $stringData = "$(get-date) level: $level sendreport: $sendReport report: $report data:`r`n$stringData`r`n"
    write-output $stringData

    if ($global:sfClientAvailable) {
        try {
            $newLogFile = "$logDirectory\$($global:scriptName)-$((get-date).tostring('yyMMddhh')).log"
            if ($newLogFile -ine $global:datedLogFile) {
                if ($global:logStream) {
                    [void]$global:logStream.Close()
                    $global:logStream = $null
                }
            }
            if ($global:logStream -eq $null) {
                $global:datedLogFile = $newLogFile
                $global:logStream = new-object System.IO.StreamWriter ($global:datedLogFile, $true)
                $global:logTimer.Interval = 5000 #5 seconds

                Register-ObjectEvent -InputObject $global:logTimer -EventName elapsed -SourceIdentifier logTimer -Action `
                { 
                    Unregister-Event -SourceIdentifier logTimer | out-null
                    [void]$global:logStream.Close() 
                    $global:logStream = $null
                }

                $global:logTimer.start() 
            }

            # reset timer
            $global:logTimer.Interval = 5000 #5 seconds
            $global:logStream.WriteLine("$([DateTime]::Now.ToString())::$([Diagnostics.Process]::GetCurrentProcess().ID)::$($stringData)")
        }
        catch {
            Write-error "write-log:exception $($_):$($error)"
            $error.Clear()
        }
    }
    

    if ($sendReport -and $global:sfClientAvailable) {
        try {
            if (!(get-serviceFabricClusterConnection)) { connect-servicefabriccluster }
            $error.clear()

            if (!$report) { $report = ($jobName, $global:scriptName -ne $null)[0] }

            write-output "$(get-date) Send-ServiceFabricNodeHealthReport 
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
                -Description "$stringData" | Out-Null
        }
        catch {
            write-output "error sending report: $(($error | out-string))"
            write-error ($error | out-string)
            $error.Clear()
        }
    }

    return $null
}


# execute script
main
#