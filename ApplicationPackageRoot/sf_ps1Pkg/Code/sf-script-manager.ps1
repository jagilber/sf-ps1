#
[cmdletbinding()]
param(
    [string[]]$scripts = @()
)

$errorActionPreference = "silentlycontinue"
$global:joboutputs = @{}
$global:fail = 0
$global:success = 0

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
            write-log ($job | fl * | out-string)

            if ($job.state -ieq "completed") { # -ine "running") {
                write-log ($job | fl * | out-string)
                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job | ConvertTo-Json))
                    $global:fail++
                }
                else {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job.output | ConvertTo-Json))
                    $global:success++
                }
                write-log ($job.output | ConvertTo-Json)
                $job.output
                Remove-Job -Id $job.Id -Force  
            }
            else {
                $jobInfo = Receive-Job -Job $job
                
                if ($jobInfo) {
                    write-log ($jobInfo | fl * | out-string)
                }
            }
            Start-Sleep -Seconds 1
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
    write-log "start jobs"
    foreach ($script in @($scripts)) {
        $argIndex = $script.LastIndexOf('.ps1') + 4
        $scriptFile = $script.substring(0, $argIndex)
        $scriptArgs = $script.substring($argIndex)
        $scriptFileName = [io.path]::GetFileName($scriptFile)
        write-log "checking file:$scriptFileName`r`n`targs:$scriptArgs"

        if($scriptFile.tolower().startswith("http")) {
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
            param($script,$args)
            write-log "$script $args"
            write-log (invoke-expression -command "$script $args")
        }
    }
}

function write-log($data, $level) {
    $data = "$(get-date):$data`r`n"

    if($level -imatch "error") {
        write-error $data
    }
    elseif($level -imatch "warning") {
        Write-Warning $data
    }

    write-host $data
}

# execute script
main
#