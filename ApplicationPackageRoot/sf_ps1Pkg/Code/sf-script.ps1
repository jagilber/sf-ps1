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

while ($true) {
    $netStat = @{ }
    $timer = get-date
    Connect-ServiceFabricCluster

    $netStatRaw = Get-NetTCPConnection 
    $netStatSelected = $netStatRaw | select LocalPort, State
    $netStatSelected | group State | % { $netStat["$($_.Name)_Conn"] = $_.Count }
    $netStatSelected | sort State, LocalPort | select -Unique State, LocalPort | group State | % { $netStat["$($_.Name)_Ports"] = $_.Count }
    $netStatObj = $netStat.GetEnumerator() | sort name | % -Begin { [PSObject]$o = @{ } } { $o | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } -End { $o }

    $msg = "$(get-date) all: $($netstatRaw.Count)`r`n$($netStatObj | ConvertTo-Json)`r`n"
    $netStatProcess = $netStatRaw | where-object OwningProcess -eq (get-process $processName).id
    $netStatProcessGrouped = $netStatProcess | group state
    $msg += "$(get-date) $($processName): $($netStatProcess.Count)`r`n$($netStatProcessGrouped | out-string)`r`n"
    $msg += "timer: $(((get-date) - $timer).tostring())"
    write-host $msg
    
    $level = 'Ok'
    if ($netStatProcess.count -gt ($maxConnectionCount * .8)) {
        $level = 'Warning'
    }
    elseif ($netStatProcess.Count -ge $maxConnectionCount) {
        $level = 'Error'
    }

    $error.clear()
    write-host "Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId $source -HealthProperty 'NetStat' -Description $msg"
    $result = Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId $source -HealthProperty 'NetStat' -Description $msg

    if ($error -or $result) { 
        Write-host ($result | out-string)
        Write-host ($error | out-string)
        Write-Error ($error | out-string)
        $error.Clear()
    }

    Write-Host "Sleeping for $sleepMinutes minutes"
    Start-Sleep -Seconds ($sleepMinutes * 60)
}
