###########################
# sf-ps1 template script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [int]$myErrorDescription = $env:myErrorDescription,
    [int]$myWarningDescription = $env:myWarningDescription,
    [int]$myDescription = $env:myDescription
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try {
        while ($true) {
            $timer = get-date
            write-host "$($MyInvocation.ScriptName)`r`n$myDescription`r`n" -ForegroundColor green

            {{my code}}

            if ({{my error condition}} -or $error) {
                write-error "ERROR:$myErrorDescription`r`n"
                write-host "$($error | out-string)`r`n" -ForegroundColor red
            }
            elseif ({{my warning condition}}) {
                write-warning "WARNING:$myWarningDescription`r`n"
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