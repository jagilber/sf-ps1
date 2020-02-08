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
        write-output "$($MyInvocation.ScriptName)`r`n$psboundparameters : $myDescription`r`n"

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

        if(!$isAdmin){
            write-output "error:restart script as administrator"
            return
        }

        if(Get-NetEventSession) {
            write-output "$(get-date) removing old trace session`r`n"
            #write-output (Stop-NetEventSession -Name $session)
            write-output (Get-NetEventSession | Remove-NetEventSession)
        }

        $error.Clear()
        write-output (New-NetEventSession -Name $session `
            -CaptureMode SaveToFile `
            -MaxFileSize $maxSizeMb `
            -MaxNumberOfBuffers 15 `
            -TraceBufferSize 1024 `
            -LocalFilePath $traceFile)
        

        if($withCommonProviders) {
            write-output "adding common providers`r`n"

            write-output (Add-NetEventProvider -Name "Microsoft-Windows-TCPIP" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0)

            write-output (Add-NetEventProvider -Name "{DD5EF90A-6398-47A4-AD34-4DCECDEF795F}" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0)

            write-output (Add-NetEventProvider -Name "{20F61733-57F1-4127-9F48-4AB7A9308AE2}" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0)

            write-output (Add-NetEventProvider -Name "Microsoft-Windows-HttpLog" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0)

            write-output (Add-NetEventProvider -Name "Microsoft-Windows-HttpService" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0)

            write-output (Add-NetEventProvider -Name "Microsoft-Windows-HttpEvent" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0)

            write-output (Add-NetEventProvider -Name "Microsoft-Windows-Http-SQM-Provider" -SessionName $session `
                -Level 4 `
                -MatchAnyKeyword ([UInt64]::MaxValue) `
                -MatchAllKeyword 0x0)

                
        }

        write-output (Add-NetEventPacketCaptureProvider -SessionName $session `
            -Level 4 `
            -MatchAnyKeyword ([UInt64]::MaxValue) `
            -MatchAllKeyword 0x0 `
            -MultiLayer $true)
        

        write-output "$(get-date) starting trace`r`n"
        Start-NetEventSession -Name $session
        Get-NetEventSession -Name $session

        write-output "$(get-date) sleeping $sleepMinutes minutes`r`n"
        start-sleep -Seconds ($sleepMinutes * 60)

        write-output "$(get-date) checking trace`r`n"
        write-output (Get-NetEventSession -Name $session)
        

        write-output "$(get-date) stopping trace`r`n"
        write-output (Stop-NetEventSession -Name $session)
        

        write-output "$(get-date) removing trace`r`n"
        write-output (Remove-NetEventSession -Name $session)
        
        write-output (Get-WinEvent -Path $traceFile -Oldest | Select-Object TimeCreated, ProcessId, ThreadId, RecordId, Message | ConvertTo-Csv | out-file $csvFile)
        
        if ($error) {
            write-output "ERROR:$myErrorDescription`r`n"
            write-output "$($error | out-string)`r`n"
        }

        write-output "copying files`r`n"
        copy net.* ..\log
        
        write-output "$(get-date) timer: $(((get-date) - $timer).tostring())`r`n"
        write-output "$(get-date) finished`r`n"
        
    }
    catch {
        write-output ($_ | out-string)
        write-output ($error | out-string)
        
	}
}

main