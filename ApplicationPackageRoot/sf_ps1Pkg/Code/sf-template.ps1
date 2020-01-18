###########################
# sf-ps1 template script
# 
###########################
param(
    $sleepMinutes = 1,
    $myErrorDescription = "",
    $myWarningDescription = "",
    $myDescription = ""
)

$ErrorActionPreference = "continue"

function main() {
    while ($true) {
        $timer = get-date
        $msg = "$($MyInvocation.ScriptName): $myDescription`r`n"

        {{my code}}

        if ({{my error condition}}) {
            $msg += "ERROR:$myErrorDescription`r`n"
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