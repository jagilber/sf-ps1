#
# draft
#

param(
    [ValidateSet('livekd.exe', 'psexec.exe', 'procmon.exe', 'procdump.exe', 'procexp.exe', 'tcpview.exe', 'rammap.exe', 'handle.exe')]
    [string]$sysInternalsExe = ($env:sysInternalsExe, "procdump.exe" -ne $null)[0],
    [string]$sysInternalsExeStartCommand = ($env:sysInternalsExeStartCommand, "-accepteula" -ne $null)[0],
    [string]$sysInternalsExeStopCommand = ($env:sysInternalsExeStopCommand, "" -ne $null)[0],
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*.*" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [switch]$noExecute = $env:noExecute,
    [switch]$removeAllSysinternalInstances = ($env:removeAllSysinternalInstances, $true -ne $null)[0],
    [switch]$requiresAdmin = $env:requiresAdmin
)

write-host "$(get-date) `r`n$psboundparameters"
[net.ServicePointManager]::Expect100Continue = $true
[net.ServicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12

$ErrorActionPreference = "continue"
$error.clear()

function main() {
    try {
        $timer = get-date
        $process = $null
        write-host "$($MyInvocation.ScriptName)`r`n$($psboundparameters | out-string) : $myDescription`r`n" -ForegroundColor Green

        if(!$env:Path.Contains($pwd)) {
            $env:Path += ";$pwd"
            write-host "$(get-date) new path $env:Path" -ForegroundColor Green
        }

        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

        if($requiresAdmin -and !$isAdmin){
            write-error "error:restart script as administrator"
            return
        }

        if (!(test-path $sysinternalsexe)) {
            write-host "$(get-date) downloading $sysinternalsExe" -ForegroundColor Green
            (new-object net.webclient).DownloadFile("http://live.sysinternals.com/$sysinternalsexe", "$pwd\$sysinternalsexe")
        }

        if ($noExecute) {
            write-host "$(get-date) noexecute returning" -ForegroundColor Green
        }

        $error.Clear()
        write-host "$(get-date) starting $sysinternalsExe $sysinternalsExeStartCommand" -ForegroundColor Green
        $process = start-process -PassThru -FilePath $sysinternalsexe -ArgumentList $sysinternalsExeStartCommand
        write-host "$(get-date) starting process info: $($process | fl * | out-string)" -ForegroundColor Green

        if($error -or !$process -or $process.ExitCode)
        {
            write-error "$(get-date) $($error | out-string) $($process | out-string)"
            return
        }

        write-host "$(get-date) sleeping for $sleepMinutes minutes`r`n" -ForegroundColor Green
        #start-sleep -Seconds ($sleepMinutes * 60)
        Wait-Process -Id $process.id -Timeout ($sleepMinutes * 60) -ErrorAction SilentlyContinue
        write-host "$(get-date) waiting process info: $($process | fl * | out-string)" -ForegroundColor Green

        if(($error -or !$process) -or ($process.ExitCode -and $process.ExitCode -ne 0))
        {
            write-error "error:$(get-date) $($error | out-string) $($process | fl * | out-string)"
        }

        if($sysinternalsExeStopCommand) {
            write-host "$(get-date) stopping $sysinternalsExe $sysinternalsExeStopCommand" -ForegroundColor Green
            $process = start-process -PassThru -FilePath $sysinternalsexe -ArgumentList $sysinternalsExeStopCommand
            write-host "$(get-date) stopping process info: $($process | fl * | out-string)" -ForegroundColor Green
        }
        else {
            write-host "$(get-date) killing $sysinternalsExe" -ForegroundColor Green
            #stop-process -Id $process.Id -Force
            # procdump wants ctrl-c to detach
            $process.CloseMainWindow()
            
            write-host "$(get-date) killing process info: $($process | fl * | out-string)" -ForegroundColor Green
            if($removeAllSysinternalInstances) {
                $wildName = "$([io.path]::GetFileNameWithoutExtension($sysinternalsexe))*"
                stop-process -name $wildName -Force
                write-host "$(get-date) killing proces name $wildName : $($process | fl * | out-string)" -ForegroundColor Green
            }
        }

        write-host "$(get-date) copying files $outputFilePattern to $outputFileDestination" -ForegroundColor green
        copy-item $outputFilePattern $outputFileDestination

        write-host "$(get-date) finished" -ForegroundColor Green
        write-host "$(get-date) timer: $(((get-date) - $timer).tostring())" -ForegroundColor Green
    }
    catch {
        write-error "exception:$($_ | fl * | out-string)"
        write-error "$($error | fl * | out-string)`r`n$(get-pscallstack | fl * | out-string)"
    }
}

main