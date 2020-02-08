###########################
# sf-ps1 template script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [int]$sampleInterval = ($env:sleepInterval, 1 -ne $null)[0],
    [int]$maxSamples = ($env:maxSamples, 1 -ne $null)[0],
    [string[]]$counters = ($env:counters, @("\Processor(_Total)\% Processor Time","\memory\% committed bytes in use","\physicaldisk(_total)\current disk queue length") -ne $null)[0],
    [int]$myDescription = $env:myDescription
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try {
        while ($true) {
            $timer = get-date
            write-host "$($MyInvocation.ScriptName)`r`n$myDescription`r`n" -ForegroundColor green

            foreach($counter in $counters) {
                Get-Counter -counter $counter -sampleInterval $sampleInterval -maxSamples $maxSamples
            }

            if ($error) {
                write-host "$($error | out-string)`r`n" -ForegroundColor red
            }

            write-host "sleeping for $sleepMinutes minutes`r`n" -ForegroundColor Green
            write-host "$(get-date) timer: $(((get-date) - $timer).tostring())" -ForegroundColor Green
            start-sleep -Seconds ($sleepMinutes * 60)
        }
    }
    catch {
        write-error "exception:$($_ | out-string)"
        write-error "$($error | out-string)"
	}
}

main