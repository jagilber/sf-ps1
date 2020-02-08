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
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0],
    [string]$csvFile = ($env:csvFile, "$pwd\net.csv" -ne $null)[0],
    [bool]$withCommonProviders = ($env:witCommonProviders, $true -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try{
        $session = "nettrace"        
        $timer = get-date
        write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters : $myDescription`r`n"

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

        if(!$isAdmin){
            write-host "error:restart script as administrator"
            return
        }

        if(Get-NetEventSession) {
            write-host "$(get-date) removing old trace session`r`n"
            #write-host (Stop-NetEventSession -Name $session)
            write-host (Get-NetEventSession | Remove-NetEventSession)
        }

        $error.Clear()
        New-NetEventSession -Name $session `
            -CaptureMode SaveToFile `
            -MaxFileSize $maxSizeMb `
            -MaxNumberOfBuffers 15 `
            -TraceBufferSize 1024 `
            -LocalFilePath $traceFile
        

        if($withCommonProviders) {
            write-host "adding common providers`r`n"

            Add-NetEventProvider -Name "Microsoft-Windows-TCPIP" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0

            Add-NetEventProvider -Name "{DD5EF90A-6398-47A4-AD34-4DCECDEF795F}" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0

            Add-NetEventProvider -Name "{20F61733-57F1-4127-9F48-4AB7A9308AE2}" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0

            Add-NetEventProvider -Name "Microsoft-Windows-HttpLog" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0

            Add-NetEventProvider -Name "Microsoft-Windows-HttpService" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0

            Add-NetEventProvider -Name "Microsoft-Windows-HttpEvent" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0

            Add-NetEventProvider -Name "Microsoft-Windows-Http-SQM-Provider" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0

                
        }

        Add-NetEventPacketCaptureProvider -SessionName $session `
            -Level 4 `
            -MatchAnyKeyword ([UInt64]::MaxValue) `
            -MatchAllKeyword 0x0 `
            -MultiLayer $true
        

        write-host "$(get-date) starting trace`r`n"
        Start-NetEventSession -Name $session
        Get-NetEventSession -Name $session

        write-host "$(get-date) sleeping $sleepMinutes minutes`r`n"
        start-sleep -Seconds ($sleepMinutes * 60)

        write-host "$(get-date) checking trace`r`n"
        Get-NetEventSession -Name $session
        

        write-host "$(get-date) stopping trace`r`n"
        Stop-NetEventSession -Name $session
        

        write-host "$(get-date) removing trace`r`n"
        write-host (Remove-NetEventSession -Name $session)
        
        Get-WinEvent -Path $traceFile -Oldest | Select-Object TimeCreated, ProcessId, ThreadId, RecordId, Message | ConvertTo-Csv | out-file $csvFile
        
        if ($error) {
            write-error "ERROR:$myErrorDescription`r`n"
            write-error "$($error | out-string)`r`n"
        }

        write-host "copying files`r`n"
        copy net.* ..\log
        
        write-host "$(get-date) timer: $(((get-date) - $timer).tostring())`r`n"
        write-host "$(get-date) finished`r`n"
        
    }
    catch {
        write-error ($_ | out-string)
        write-error ($error | out-string)
        
	}
}

main