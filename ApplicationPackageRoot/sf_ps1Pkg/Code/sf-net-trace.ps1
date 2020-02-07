###########################
# sf-ps1 netsh network trace
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [string]$myErrorDescription = ($env:myErrorDescription, "capture network trace with netsh" -ne $null)[0],
    [string]$myDescription = ($env:myDescription, "capture network trace with netsh" -ne $null)[0],
    [string]$traceFile = ($env:traceFile, "$pwd\net.etl" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try{
        $timer = get-date
        $msg = "$($MyInvocation.ScriptName)`r`n$psboundparameters : $myDescription`r`n"
        write-output $msg
        $session = "nettrace"

        $msg = netsh trace start capture=yes overwrite=yes maxsize=$maxSizeMb tracefile=$traceFile filemode=circular
        <#
        $csvFile = "net.csv"
        if(Get-NetEventSession -Name $session) {
            Stop-NetEventSession -Name $session
            Remove-NetEventSession -Name $session
        }

        $error.Clear()
        New-NetEventSession -Name $session -CaptureMode SaveToFile -MaxFileSize 1024 -MaxNumberOfBuffers 15 -TraceBufferSize 1024 -LocalFilePath $pwd\$traceFile
        Add-NetEventProvider -Name "Microsoft-Windows-TCPIP" -SessionName $session
        Add-NetEventPacketCaptureProvider -SessionName $session
        Start-NetEventSession -Name $session
        #>        
        write-output $msg
        start-sleep -Seconds ($sleepMinutes * 60)

        $msg += netsh trace stop
        #Stop-NetEventSession -Name $session
        #Remove-NetEventSession -Name $session
        write-output $msg

        # Get-WinEvent -Path $pwd\$traceFile -Oldest | Select-Object TimeCreated, ProcessId, ThreadId, RecordId, Message | ConvertTo-Csv | out-file $pwd\$csvFile

        if ($error) {
            $msg += "ERROR:$myErrorDescription`r`n"
            $msg += "$($error | out-string)`r`n"
        }

        $msg += "copying files"
        copy net.* ..\log

        $msg += "$(get-date) timer: $(((get-date) - $timer).tostring())"
        write-output $msg
    }
    catch {
        $msg += ($_ | out-string)
        $msg += ($error | out-string)
        write-output $msg
	}

}

main