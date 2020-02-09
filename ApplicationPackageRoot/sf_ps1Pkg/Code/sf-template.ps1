###########################
# sf-ps1 template script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [int]$myErrorDescription = ($env:myErrorDescription, "" -ne $null)[0],
    [int]$myWarningDescription = ($env:myWarningDescription, "" -ne $null)[0],
    [int]$myDescription = ($env:myDescription, "" -ne $null)[0],
    [bool]$continuous = ($env:continuous, $true -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try {
        do {
            $timer = get-date
            write-host "$(get-date) $($MyInvocation.ScriptName)`r`n$myDescription`r`n" -ForegroundColor green

            {{my code}}

            if ({{my error condition}} -or $error) {
                write-error "ERROR:$(get-date) $myErrorDescription`r`n"
                write-host "$(get-date) $($error | out-string)`r`n" -ForegroundColor red
            }
            
            if ({{my warning condition}}) {
                write-warning "WARNING:$(get-date) $myWarningDescription`r`n"
            }

            write-host "$(get-date) sleeping for $sleepMinutes minutes`r`n" -ForegroundColor Green
            write-host "timer: $(((get-date) - $timer).tostring())" -ForegroundColor Green
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