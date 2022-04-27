###########################
# sf-ps1 netsh network trace
# 
###########################
<#
.SYNOPSIS 
service fabric hns etl tracing script

.DESCRIPTION
script will create a permanent ETL tracing session across reboots using powershell Autologger cmdlets.
default destination ($traceFilePath) is configured location used by FabricDCA for log staging.
files saved in D:\SvcFab\Log\CrashDumps\ will by uploaded by FabricDCA to 'sflogs' storage account fabriccrashdumps-{{cluster id}} container.
after upload, local files will be deleted by FabricDCA automatically.
default argument values should work for most scenarios.
add / remove etw tracing guids as needed. see get-etwtraceprovider / logman query providers
to remove tracing use -remove switch.

https://docs.microsoft.com/powershell/module/eventtracingmanagement/Start-EtwTraceSession

.LINK
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/sf-hns-tracing.ps1" -outFile "$pwd\sf-hns-tracing.ps1";
.\sf-hns-tracing.ps1

#>

[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 1 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [string]$outputFile = ($env:outputFile, "$pwd\$env:computername-net.$((get-date).tostring("MMddhhmmss")).etl" -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*net.*.etl" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0],
    [string[]]$traceGuids = ($env:traceGuids, @(
            '{2F07E2EE-15DB-40F1-90EF-9D7BA282188A}' # Microsoft-Windows-TCPIP
        ) -ne $null)[0],
    [string]$traceName = 'sf-etl',
    # new file https://docs.microsoft.com/windows/win32/etw/logging-mode-constants
    $logFileMode = 8,

    # output file name and path
    $traceFilePath = 'D:\SvcFab\Log\CrashDumps\sf%d.etl',

    # output file size in MB
    $maxFileSizeMb = 64,

    # max ETW trace buffers
    $maxBuffers = 16,

    # buffer size in MB
    $bufferSize = 1024,

    # 6 == everything
    $level = 6,

    # 0xFFFFFFFFFFFFFFFF == everything
    $keyword = 18446744073709551615
)

$ErrorActionPreference = "continue"
write-host "$($psboundparameters | Format-List * | out-string)`r`n" -ForegroundColor green

function main() {
    try {
        do {
            $error.clear()
            $timer = get-date
            write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters`r`n"
            if (!(check-admin)) { return }

            # remove existing trace
            stop-command

            # start new trace
            start-command
            check-error
            wait-command
            $timer = get-date

            # stop new trace
            stop-command
            check-error

            # copy trace
            copy-files

            write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
            write-host "$(get-date) finished" -ForegroundColor green
        }
        while ($continuous) 
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
    }
}

function check-admin() {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (!$isAdmin) {
        write-error "error:restart script as administrator"
        return $false
    }

    return $true
}

function check-error() {
    if ($error) {
        write-error "$(get-date) $($error | Format-List * | out-string)"
        write-host "$(get-date) $($error | Format-List * | out-string)"
        $error.Clear()
        return $true
    }
    return $false
}

function copy-files($source = $outputFilePattern, $destination = $outputFileDestination) {
    if ($destination) {
        write-host "$(get-date) moving files $source to $destination"
        if (!(test-path $destination) -and !(new-item -Path $destination -ItemType Directory)) {
            write-error "$(get-date) unable to create directory $destination"
        }
        else {
            foreach ($item in get-item -path $source) {
                $error.Clear()
                write-host "$(get-date) compress-archive -Path $item -DestinationPath $destination\$([io.path]::GetFileNameWithoutExtension($item)).zip"
                compress-archive -Path $item -DestinationPath "$destination\$([io.path]::GetFileNameWithoutExtension($item)).zip" -Force
                if (!$error) {
                    write-host "$(get-date) removing $item"
                    remove-item $item -Force -Recurse
                }
            }
        }
    }
}

function stop-command() {
    write-host "$(get-date) stopping existing trace`r`n" -ForegroundColor green
    if ((Get-EtwTraceSession -Name $traceName)) {
        write-warning "Stop-EtwTraceSession -Name $traceName"
        Stop-EtwTraceSession -Name $traceName
    }
}

function start-command() {

    $error.Clear()

    write-host "$(get-date) starting trace" -ForegroundColor green
    
    write-host "
    Start-EtwTraceSession -Name $traceName ``
        -LogFileMode $logFileMode ``
        -LocalFilePath $traceFilePath ``
        -MaximumFileSize $maxFileSizeMb ``
        -MaximumBuffers $maxBuffers ``
        -BufferSize $bufferSize
    " -ForegroundColor Cyan

    Start-EtwTraceSession -Name $traceName `
        -LogFileMode $logFileMode `
        -LocalFilePath $traceFilePath `
        -MaximumFileSize $maxFileSizeMb `
        -MaximumBuffers $maxBuffers `
        -BufferSize $bufferSize

    foreach ($guid in $traceGuids) {
        write-host "adding $guid
        Add-EtwTraceProvider -SessionName $traceName ``
            -Guid $guid ``
            -Level $level ``
            -MatchAnyKeyword $keyword
        " -ForegroundColor Cyan

        Add-EtwTraceProvider -SessionName $traceName `
            -Guid $guid `
            -Level $level `
            -MatchAnyKeyword $keyword

    }

    Get-EtwTraceSession -Name $traceName | format-list *
    logman query -ets $traceName
}

function wait-command($minutes = $sleepMinutes, $currentTimer = $timer) {
    write-host "$(get-date) timer: $(((get-date) - $currentTimer).tostring())"
    write-host "$(get-date) sleeping $minutes minutes" -ForegroundColor green
    start-sleep -Seconds ($minutes * 60)
    write-host "$(get-date) resuming" -ForegroundColor green
    write-host "$(get-date) timer: $(((get-date) - $currentTimer).tostring())"
}

main