###########################
# sf-ps1 template script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [string]$command = ($env:command, "" -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try {
        do {
            set-location $psscriptroot
            $startTimer = get-date
            write-host "$(get-date) $($MyInvocation.ScriptName)`r`n" -ForegroundColor green
            set-location $psscriptroot
            $result = Invoke-Expression -Command $command

            if ($error) {
                write-error "$(get-date) $($error | out-string)"
                $error.Clear()
            }

            write-host "whoami: $(whoami) output: $(dir $psscriptroot\outfile* -recurse)"
            write-host "result: $($result | out-string)"
            write-host "output: $(dir outfile* -recurse)"
            write-host "timer: $(((get-date) - $timer).tostring())" -ForegroundColor Green
            write-host "$(get-date) sleeping for $sleepMinutes minutes`r`n" -ForegroundColor Green
            start-sleep -Seconds ($sleepMinutes * 60)
        }
        while ($continuous) 
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
	}
}

write-host "$($psboundparameters | fl * | out-string)`r`n" -ForegroundColor green
main