###########################
# TCP connection stats
###########################
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [string[]]$processNames = ($env:ProcessNames, @("fabric","fabrichost","fabricgateway") -ne $null)[0],
    $maxConnectionCount = ($env:maxConnectionCount, 1000 -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

$result = netsh int ipv4 show dynamicportrange tcp
$match = [regex]::Match($result, `
    "Start Port\s+:\s+(?<startPort>\d+).+?Number of Ports\s+:\s+(?<numberOfPorts>\d+)", `
    [text.RegularExpressions.RegexOptions]::Singleline -bor [text.RegularExpressions.RegexOptions]::IgnoreCase)
$ephemStartPort = [convert]::ToInt32($match.Groups["startPort"].Value)
$ephemPortCount = [convert]::ToInt32($match.Groups["numberOfPorts"].Value)
$ephemEndPort = $ephemStartPort + $ephemPortCount - 1

while ($true) {
    $startTimer = get-date
    $netStat = @{ }

    $netStatRaw = Get-NetTCPConnection 
    $netStatSelected = $netStatRaw | select-object LocalPort, State

    foreach($netStatItem in ($netStatSelected | group-object State)) {
        $netStat.Add("$($netStatItem.Name)_Conn", $netStatItem.Count)
    }

    foreach($netStatItem in ($netStatSelected | select-object -Unique State, LocalPort | group-object State)) {
        $netStat.Add("$($netStatItem.Name)_Ports", $netStatItem.Count)
    }

    $ephemPortsInUse = @($netStatSelected | select-object -Unique LocalPort | where-object {($_.LocalPort -ge $ephemStartPort -and $_.LocalPort -le $ephemEndPort) }).Count

    $msg = "`r`nephemeral port range: $ephemStartPort - $ephemEndPort`r`n"
    $msg += "ephemeral ports available: $($ephemPortCount - $ephemPortsInUse)`r`n"
    $msg += "ephemeral ports in use: $ephemPortsInUse`r`n"
    $msg += "`r`ntotal network ports in use: $($netstatRaw.Count)`r`n$($netStat | convertto-json )`r`n"

    foreach($processName in @($processNames)) {
        foreach($id in (get-process $processName).id) {
            $netStatProcess = @($netStatRaw | where-object OwningProcess -eq $id)
            $netStatProcessGrouped = $netStatProcess | group-object state
            $msg += "$processName pid: $id `r`nports in use: $($netStatProcess.Count)`r`n$($netStatProcessGrouped | out-string)`r`n"

            if ($netStatProcess.Count -ge $maxConnectionCount) {
                $msg += "ERROR: $processName count over max connection count $maxConnectionCount`r`n"
            }
            elseif ($netStatProcess.count -gt ($maxConnectionCount * .8)) {
                $msg += "WARNING: $processName connection count near max connection count $maxConnectionCount`r`n"
            }
        }
    }

    if ($ephemPortsInUse -ge $ephemPortCount) {
        $msg += "ERROR: ephemeral port count >= max ephemeral connection count $ephemPortCount`r`n"
    }
    elseif ($ephemPortsInUse -gt ($ephemPortCount * .8)) {
        $msg += "WARNING: ephemeral port count near max ephemeral connection count $ephemPortCount`r`n"
    }

    $msg += "sleeping for $sleepMinutes minutes`r`n"
    $msg += "$(get-date) timer: $(((get-date) - $startTimer).tostring())"
    write-output $msg
    
    start-sleep -Seconds ($sleepMinutes * 60)
}
