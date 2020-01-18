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
        write-host "starting"
        remove-jobs
        start-jobs
        monitor-jobs
    }
    catch {
        write-error ($error | out-string)
    }
    finally {
        remove-jobs
        write-host "finished"
    }
}

function monitor-jobs() {
    write-host "monitoring jobs"
    while (get-job) {
        foreach ($job in get-job) {
            write-verbose ($job | fl * | out-string)

            if ($job.state -ine "running") {
                write-host ($job | fl * | out-string)
                if ($job.state -imatch "fail" -or $job.statusmessage -imatch "fail") {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job | ConvertTo-Json))
                    $global:fail++
                }
                else {
                    [void]$global:joboutputs.add(($global:jobs[$job.id]), ($job.output | ConvertTo-Json))
                    $global:success++
                }
                write-host ($job.output | ConvertTo-Json)
                $job.output
                Remove-Job -Id $job.Id -Force  
            }
            else {
                $jobInfo = Receive-Job -Job $job
                
                if ($jobInfo) {
                    write-host ($jobInfo | fl * | out-string)
                }
            }
            Start-Sleep -Seconds 1
        }
    }
}

function remove-jobs() {
    write-host "removing jobs"
    try {
        if (@(get-job).Count -gt 0) {
            foreach ($job in get-job) {
                write-host "removing job $($job.Name)"
                $job.StopJob()
                Remove-Job $job -Force
            }
        }
    }
    catch {
        write-host $Error
        $error.Clear()
    }
}

function start-jobs() {
    write-host "start jobs"
    foreach ($script in $scripts) {
        $argIndex = $script.LastIndexOf('.ps1') + 4
        $scriptFile = $script.substring(0, $argIndex)
        $scriptFileName = [io.path]::GetFileName($scriptFile)
        $scriptArgs = $script.substring($argIndex)
        write-host "checking file:$scriptFile`r`n`targs:$scriptsArgs"

        if($scriptFile.tolower().startswith("http")) {
            write-host "downloading $scriptFile"
            $downloadedFile = "$env:temp\$scriptFileName"
            (new-object net.webclient).DownloadFile($scriptFile, $downloadedFile)
            $scriptFile = $downloadedFile
        }
        elseif(!(test-path $scriptFile)) {
            write-error "$scriptFile does not exist"
            continue
        }

        $scriptFile = resolve-path $scriptFile
        write-host "starting $scriptFile $scriptArgs"
        start-job -Name $scriptFileName -ArgumentList @($scriptFile, $scriptArgs) -scriptblock { 
            param($script,$args)
            write-output "$script $args"
            write-output (invoke-expression -command "$script $args")
        }
    }
}

# execute script
main
#