###########################
# sf-ps1 template script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try {
        do {
            #set-location $psscriptroot
            $timer = get-date
            write-host "$(get-date) $($MyInvocation.ScriptName)`r`n" -ForegroundColor green

            {{my code}}

            if ({{my error condition}} -or $error) {
                write-error "$(get-date) $($error | out-string)"
                $error.Clear()
            }
            
            if ({{my warning condition}}) {
                write-warning "WARNING:$(get-date)`r`n"
            }

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