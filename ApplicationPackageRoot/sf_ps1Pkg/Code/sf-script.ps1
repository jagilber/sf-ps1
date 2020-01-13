###########################
# TCP connection stats
###########################
param(
	$sleepMinutes = 1,
    $nodeName = $env:Fabric_NodeName
)

while ($true) {
    $netStat = @{ }
    Connect-ServiceFabricCluster

	$netStatRaw = Get-NetTCPConnection 
    $netStatSelected = $netStatRaw | select LocalPort, State
	$netStatSelected | group State | % { $netStat["$($_.Name)_Conn"] = $_.Count }
	$netStatSelected | sort State, LocalPort | select -Unique State, LocalPort | group State | % { $netStat["$($_.Name)_Ports"] = $_.Count }
	$netStatObj = $netStat.GetEnumerator() | sort name | % -Begin { [PSObject]$o = @{ } } { $o | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value } -End { $o }

	$msg = "$(get-date) all:`r`n$($netStatObj | ConvertTo-Json)`r`n"
	$netStatFG = $netStatRaw | where-object OwningProcess -eq (get-process fabricgateway).id
    $netSTatFGGrouped = $netStatFG | group state
	$msg += "$(get-date) fabricgateway:`r`n$($netStatFGGrouped | out-string)`r`n"
    write-host $msg
    
    $level = 'Ok'
    if($netStatFG.count -gt 800)
    {
        $level = 'Warning'
    }
    elseif($netStatFG.Count -ge 1000)
    {
        $level = 'Error'
    }


	$error.clear()
	write-host "Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId 'NodeErrata' -HealthProperty 'NetStat' -Description $msg"
	$result = Send-ServiceFabricNodeHealthReport -NodeName $nodeName -HealthState $level -SourceId 'NodeErrata' -HealthProperty 'NetStat' -Description $msg
    if($error -or $result) 
    { 
        Write-host ($result | out-string)
        Write-host ($error | out-string)
        Write-Error ($error | out-string)
        $error.Clear()
    }

	Write-Host "Sleeping for $sleepMinutes minutes"
	Start-Sleep -Seconds ($sleepMinutes * 60)
}
