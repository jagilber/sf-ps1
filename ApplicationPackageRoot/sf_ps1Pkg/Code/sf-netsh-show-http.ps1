###########################
# netsh show http cert info
###########################
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

while ($true) {
    $timer = get-date
    $msg = "`r`nnetsh http show sslcert: $(netsh http show sslcert|out-string)`r`n"

    $msg += "sleeping for $sleepMinutes minutes`r`n"
    $msg += "$(get-date) timer: $(((get-date) - $timer).tostring())"
    write-output $msg
    
    start-sleep -Seconds ($sleepMinutes * 60)
}
