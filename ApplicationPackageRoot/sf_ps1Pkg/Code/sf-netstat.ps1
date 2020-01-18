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

$ErrorActionPreference = "silentlycontinue"

while ($true) {
    $netStat = @{ }
    $timer = get-date
    Connect-ServiceFabricCluster

    $netStatRaw = Get-NetTCPConnection 
    $netStatSelected = $netStatRaw | select LocalPort, State
    $netStatSelected | group State | % { $netStat["$($_.Name)_Conn"] = $_.Count }
    $netStatSelected | sort State, LocalPort | select -Unique State, LocalPort | group State | % { $netStat["$($_.Name)_Ports"] = $_.Count }
    $netStatObj = $netStat.GetEnumerator() | sort name | % -Begin { [PSObject]$o = @{ } } { $o | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } -End { $o }

    $msg = "all: $($netstatRaw.Count)`r`n$($netStatObj | ConvertTo-Json)`r`n"
    $netStatProcess = $netStatRaw | where-object OwningProcess -eq (get-process $processName).id
    $netStatProcessGrouped = $netStatProcess | group state
    $msg += "$($processName): $($netStatProcess.Count)`r`n$($netStatProcessGrouped | out-string)`r`n"
    
    $level = 'Ok'
    if ($netStatProcess.Count -ge $maxConnectionCount) {
        $level = 'Error'
        $msg += "ERROR: $processName count over max connection count $maxConnectionCount`r`n"
    }
    elseif ($netStatProcess.count -gt ($maxConnectionCount * .8)) {
        $level = 'Warning'
        $msg += "WARNING: $processName connection count near max connection count $maxConnectionCount`r`n"
    }

    $msg += "$(get-date) timer: $(((get-date) - $timer).tostring())`r`n"
    write-output $msg

    write-host "Sleeping for $sleepMinutes minutes`r`n"
    start-sleep -Seconds ($sleepMinutes * 60)
}
