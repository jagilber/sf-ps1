###########################
# sf-ps1 perfmon
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*.blg" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputDestination, "..\log" -ne $null)[0]
)

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try {
        do {
            $timer = get-date
            write-host "$(get-date) $($MyInvocation.ScriptName)`r`n" -ForegroundColor green
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

            if(!$isAdmin){
                write-error "error:restart script as administrator"
                return
            }

            write-host "$(get-date) deleting existing Perfmon sessions (error is ok)"
            write-host "$(get-date) logman delete PerfLog-Long"
            logman delete PerfLog-Long
            
            write-host "$(get-date) logman delete PerfLog-Short"
            logman delete PerfLog-Short

            write-host "$(get-date) starting Perfmon"
            #long perf
            write-host "logman create counter PerfLog-Long -o '$pwd\$env:computername-PerfLog-Long.blg' -f bincirc -v mmddhhmm -max 300 -c '\LogicalDisk(*)\*' '\Memory\*' '\.NET CLR Exceptions(*)\*' '\.NET CLR Memory(*)\*' '\Cache\*' '\Network Interface(*)\*' '\Netlogon(*)\*' '\Paging File(*)\*' '\PhysicalDisk(*)\*' '\Processor(*)\*' '\Processor Information(*)\*' '\Process(*)\*' '\Server\*' '\System\*' '\Server Work Queues(*)\*' -si 00:05:00"
            logman create counter PerfLog-Long -o "$pwd\$env:computername-PerfLog-Long.blg" -f bincirc -v mmddhhmm -max 300 -c '\LogicalDisk(*)\*' '\Memory\*' '\.NET CLR Exceptions(*)\*' '\.NET CLR Memory(*)\*' '\Cache\*' '\Network Interface(*)\*' '\Netlogon(*)\*' '\Paging File(*)\*' '\PhysicalDisk(*)\*' '\Processor(*)\*' '\Processor Information(*)\*' '\Process(*)\*' '\Server\*' '\System\*' '\Server Work Queues(*)\*' -si 00:05:00

            #short perf
            write-host "logman create counter PerfLog-Short -o '$pwd\$env:computername-PerfLog-Short.blg' -f bincirc -v mmddhhmm -max 300 -c '\LogicalDisk(*)\*' '\Memory\*' '\.NET CLR Exceptions(*)\*' '\.NET CLR Memory(*)\*' '\Cache\*' '\Network Interface(*)\*' '\Netlogon(*)\*' '\Paging File(*)\*' '\PhysicalDisk(*)\*' '\Processor(*)\*' '\Processor Information(*)\*' '\Process(*)\*' '\Server\*' '\System\*' '\Server Work Queues(*)\*' -si 00:00:03"
            logman create counter PerfLog-Short -o "$pwd\$env:computername-PerfLog-Short.blg" -f bincirc -v mmddhhmm -max 300 -c '\LogicalDisk(*)\*' '\Memory\*' '\.NET CLR Exceptions(*)\*' '\.NET CLR Memory(*)\*' '\Cache\*' '\Network Interface(*)\*' '\Netlogon(*)\*' '\Paging File(*)\*' '\PhysicalDisk(*)\*' '\Processor(*)\*' '\Processor Information(*)\*' '\Process(*)\*' '\Server\*' '\System\*' '\Server Work Queues(*)\*' -si 00:00:03
            
            write-host "$(get-date) logman start PerfLog-Long"
            logman start PerfLog-Long
            
            write-host "$(get-date) logman start PerfLog-Short"
            logman start PerfLog-Short
        
            if ($error) {
                write-error "$(get-date) $($error | out-string)"
                $error.Clear()
            }

            write-host "timer: $(((get-date) - $timer).tostring())" -ForegroundColor Green
            write-host "$(get-date) sleeping for $sleepMinutes minutes`r`n" -ForegroundColor Green
            start-sleep -Seconds ($sleepMinutes * 60)

            write-host "$(get-date) logman stop PerfLog-Long"
            logman stop PerfLog-Long
            
            write-host "$(get-date) logman stop PerfLog-Short"
            logman stop PerfLog-Short

            if ($error) {
                write-error "$(get-date) $($error | out-string)"
                $error.Clear()
            }

            write-host "$(get-date) logman delete PerfLog-Long"
            logman delete PerfLog-Long
            
            write-host "$(get-date) logman delete PerfLog-Short"
            logman delete PerfLog-Short

            if ($error) {
                write-error "$(get-date) $($error | out-string)"
                $error.Clear()
            }

            if($outputFileDestination) {
                write-host "$(get-date) moving files $pwd\$outputFilePattern to $outputFileDestination"
                if(!(test-path $outputFileDestination) -and !(new-item -Path $outputFileDestination -ItemType Directory)) {
                    write-error "$(get-date) unable to create directory $outputFileDestination"
                }
                else {
                    move-item -path $pwd\$outputFilePattern -destination $outputFileDestination -Force
                }
            }
        }
        while ($continuous) 
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
	}
}

write-host "$($psboundparameters | fl * | out-string)`r`n" -ForegroundColor green
main