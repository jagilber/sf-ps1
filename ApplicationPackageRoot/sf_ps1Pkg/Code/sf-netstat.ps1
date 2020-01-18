###########################
# TCP connection stats
###########################
param(
    $sleepMinutes = 1,
    $nodeName = $env:Fabric_NodeName,
    $processName = "fabricgateway",
    $maxConnectionCount = 1000,
    $source = $env:Fabric_ServiceName
)

$ErrorActionPreference = "continue"

while ($true) {
    $netStat = @{ }
    $timer = get-date

    $netStatRaw = Get-NetTCPConnection 
    $netStatSelected = $netStatRaw | select LocalPort, State
    $netStatSelected | group State | % { $netStat["$($_.Name)_Conn"] = $_.Count }
    $netStatSelected | sort State, LocalPort | select -Unique State, LocalPort | group State | % { $netStat["$($_.Name)_Ports"] = $_.Count }
    $netStatObj = $netStat.GetEnumerator() | sort name | % -Begin { [PSObject]$o = @{ } } { $o | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } -End { $o }

    $msg = "all: $($netstatRaw.Count)`r`n$($netStatObj | ConvertTo-Json)`r`n"
    $netStatProcess = $netStatRaw | where-object OwningProcess -eq (get-process $processName).id
    $netStatProcessGrouped = $netStatProcess | group state
    $msg += "$($processName): $($netStatProcess.Count)`r`n$($netStatProcessGrouped | out-string)`r`n"
    
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
