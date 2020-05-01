###########################
# sf-ps1 etw script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 5 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [bool]$format = $true,
    [string]$outputFilePattern = ($env:outputFilePattern, "*sf_ps1_*.etl" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 64 -ne $null)[0],
    [string]$sessionName = "sf_ps1_etw_session",
    [string]$outputFile = ".\sf_ps1_etw.etl",
    [ValidateSet('circular','newfile')]
    [string]$mode = 'circular',
    [int]$buffSize = 1024,
    [int]$numBuffers = 16,
    [string]$keywords = '0xffffffffffffffff',
    [string[]]$etwProviders = @(
        'Microsoft-Windows-DNS-Client' #,
        #'{E13C0D23-CCBC-4E12-931B-D9CC2EEE27E4}' # test .net guid . do not use
    )
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = "continue"
write-host "$($psboundparameters | fl * | out-string)`r`n" -ForegroundColor green
$script:commandRunning = $false

function main() {
    try {
        set-location $psscriptroot
        $error.clear()
        $timer = get-date
        write-host "$($MyInvocation.ScriptName)`r`n$psboundparameters`r`n"
        if (!(check-admin)) { return }

        # remove existing trace
        stop-command

        # start new trace
        start-command
        check-error

        do {

            # wait
            wait-command

            if ($mode -ieq 'circular') {
                # stop new trace
                stop-command
                check-error
            }
            
            # copy trace
            copy-files

            # format files 
            format-files

            write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
        }
        while ($continuous) 
        write-host "$(get-date) finished" -ForegroundColor green
    }
    catch {
        write-error "exception:$(get-date) $($_ | out-string)"
        write-error "$(get-date) $($error | out-string)"
    }
    finally {
        if ($script:commandRunning) {
            stop-command
        }
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
        write-error "$(get-date) $($error | fl * | out-string)"
        $error.Clear()
    }
}

function copy-files($source = "$pwd\$outputFilePattern", $destination = $outputFileDestination) {
    if (!(test-path $destination) -and !(new-item -Path $destination -ItemType Directory)) {
        write-error "$(get-date) unable to create directory $destination"
        return
    }

    write-host "$(get-date) moving files $source to $destination"

    foreach ($sourceFile in (Get-ChildItem -Path $source)) {
        $destinationFile = "$destination\$([io.path]::GetFileNameWithoutExtension($sourceFile))$([io.fileinfo]::new($sourceFile).LastWriteTime.ToString('yyMMddHHmmss')).etl"
        
        if (!(test-path $destinationFile) -and !(is-fileLocked $sourceFile)) {
            write-host "$(get-date) moving file $sourceFile to $destination"
            move-item -path $sourceFile -destination $destinationFile
        }
        else {
            write-host "not moving existing destination file: $destinationFile"
        }
    }
}

function format-files($filePattern = $outputFilePattern, $destination = $outputFileDestination) {
    if ($format -and $destination) {
        write-host "$(get-date) formatting files in $destination"
        if (!(test-path $destination) -and !(new-item -Path $destination -ItemType Directory)) {
            write-error "$(get-date) unable to create directory $destination"
        }
        else {
            foreach ($file in (Get-ChildItem -recurse -Filter $filePattern -Path $destination)) {
                if(!(test-path ($file.FullName.Replace(".etl",".txt")))){
                write-host "netsh trace convert $($file.FullName)"
                    netsh trace convert $file.FullName
                }
                else {
                    write-host "not converting existing destination file: $file"
                }
            }
        }
    }
}

function is-fileLocked([string] $file) {
    $fileInfo = New-Object System.IO.FileInfo $file
 
    if ((Test-Path -Path $file) -eq $false) {
        write-host "File does not exist:$($file)"
        return $false
    }
  
    try {
        $fileStream = $fileInfo.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        if ($fileStream) {
            $fileStream.Close()
        }
 
        write-host "File is NOT locked:$($file)"
        return $false
    }
    catch {
        # file is locked by a process.
        write-host "File is locked:$($file)"
        return $true
    }
}

function start-command() {
    write-host "$(get-date) starting trace" -ForegroundColor green

    if($mode -ieq 'newfile'){
        $outputFile = "$([io.path]::GetFileNameWithoutExtension($outputFile))%d.etl"
    }
    write-host "logman create trace $sessionName -ow -o $outputFile -nb $numBuffers $numBuffers -bs $buffSize -mode $mode -max $maxSizeMb -ets"
    logman create trace $sessionName -ow -o $outputFile -nb $numBuffers $numBuffers -bs $buffSize -mode $mode -max $maxSizeMb -ets
            
    foreach ($etwProvider in $etwProviders) {
        write-host "logman update trace $sessionName -p $etwProvider $keywords 0xff -ets"
        logman update trace $sessionName -p $etwProvider $keywords 0xff -ets
    }

    logman start $sessionName -ets
    logman $sessionName -ets
    $script:commandRunning = $true
}

function stop-command() {
    write-host "$(get-date) stopping existing trace`r`n" -ForegroundColor green
    write-host "logman stop $sessionName -ets"
    logman stop $sessionName -ets
    $script:commandRunning = $false
}

function wait-command($minutes = $sleepMinutes) {
    write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
    write-host "$(get-date) sleeping $minutes minutes" -ForegroundColor green
    start-sleep -Seconds ($minutes * 60)
    write-host "$(get-date) resuming" -ForegroundColor green
    $timer = get-date
}

main