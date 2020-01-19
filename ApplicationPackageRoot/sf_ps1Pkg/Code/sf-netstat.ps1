###########################
# TCP connection stats
###########################
param(
    $sleepMinutes = 1,
    $processName = "fabricgateway",
    $maxConnectionCount = 1000
)

$ErrorActionPreference = "continue"
$result = netsh int ipv4 show dynamicportrange tcp
$match = [regex]::Match($result, `
    "Start Port\s+:\s+(?<startPort>\d+).+?Number of Ports\s+:\s+(?<numberOfPorts>\d+)", `
    [text.RegularExpressions.RegexOptions]::Singleline -bor [text.RegularExpressions.RegexOptions]::IgnoreCase);
#$ephemStartPort = $match.Groups["startPort"].Value;
$ephemPortCount = $match.Groups["numberOfPorts"].Value;

while ($true) {
    $netStat = @{ }
    $timer = get-date

    $netStatRaw = Get-NetTCPConnection 
    $netStatSelected = $netStatRaw | select-object LocalPort, State
    $netStatSelected | group-object State | foreach-object { $netStat["$($_.Name)_Conn"] = $_.Count }

    $netStatSelected | sort-object State, LocalPort | select-object -Unique State, LocalPort | group-object State | foreach-object { $netStat["$($_.Name)_Ports"] = $_.Count }
    $netStatObj = $netStat.GetEnumerator() | sort-object name | foreach-object -Begin { [PSObject]$o = @{ } } { $o | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } -End { $o }

    $msg = "`r`nephemeral ports available: $($ephemPortCount - $netstatRaw.Count)`r`n"
    $msg += "all: $($netstatRaw.Count)`r`n$($netStatObj | ConvertTo-Json)`r`n"
    $netStatProcess = $netStatRaw | where-object OwningProcess -eq (get-process $processName).id
    $netStatProcessGrouped = $netStatProcess | group-object state
    $msg += "$($processName): $($netStatProcess.Count)`r`n$($netStatProcessGrouped | out-string)`r`n"
    
    if ($netStatRaw.Count -ge $ephemPortCount) {
        $msg += "ERROR: ephemeral port count >= max ephemeral connection count $ephemPortCount`r`n"
    }
    elseif ($netStatRaw.Count -gt ($ephemPortCount * .8)) {
        $msg += "WARNING: ephemeral port count near max ephemeral connection count $ephemPortCount`r`n"
    }

    if ($netStatProcess.Count -ge $maxConnectionCount) {
        $msg += "ERROR: $processName count over max connection count $maxConnectionCount`r`n"
    }
    elseif ($netStatProcess.count -gt ($maxConnectionCount * .8)) {
        $msg += "WARNING: $processName connection count near max connection count $maxConnectionCount`r`n"
    }

    $msg += "sleeping for $sleepMinutes minutes`r`n"
    $msg += "$(get-date) timer: $(((get-date) - $timer).tostring())"
    write-output $msg
    
    start-sleep -Seconds ($sleepMinutes * 60)
}
