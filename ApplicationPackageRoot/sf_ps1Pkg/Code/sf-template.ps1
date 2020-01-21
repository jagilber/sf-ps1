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
    while ($true) {
        $timer = get-date
        $msg = "$($MyInvocation.ScriptName): $myDescription`r`n"

        {{my code}}

        if ({{my error condition}} -or $error) {
            $msg += "ERROR:$myErrorDescription`r`n"
            $msg += "$($error | out-string)`r`n"
        }
        elseif ({{my warning condition}}) {
            $msg += "WARNING:$myWarningDescription`r`n"
        }

        $msg += "sleeping for $sleepMinutes minutes`r`n"
        $msg += "$(get-date) timer: $(((get-date) - $timer).tostring())"
        write-output $msg
    
        start-sleep -Seconds ($sleepMinutes * 60)
    }
}

main