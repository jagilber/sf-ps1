# sf-ps1 utility functions

function check-admin() {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if(!$isAdmin){
        write-error "error:restart script as administrator"
        return $false
    }

    return $true
}

function check-error() {
    if ($error) {
        write-error "$(get-date) $($error | fl * | out-string)"
        write-host "$(get-date) $($error | fl * | out-string)"
        $error.Clear()
    }
}

function copy-files($source = $outputFilePattern, $destination = $outputFileDestination) {
    if($destination) {
        write-host "$(get-date) moving files $source to $destination"
        if(!(test-path $destination) -and !(new-item -Path $destination -ItemType Directory)) {
            write-error "$(get-date) unable to create directory $destination"
        }
        else {
            foreach($item in get-item -path $source) {
                $error.Clear()
                write-host "$(get-date) compress-archive -Path $item -DestinationPath $destination\$([io.path]::GetFileNameWithoutExtension($item)).zip"
                compress-archive -Path $item -DestinationPath "$destination\$([io.path]::GetFileNameWithoutExtension($item)).zip" -Force
                if(!$error) {
                    write-host "$(get-date) removing $item"
                    remove-item $item -Force -Recurse
                }
            }
        }
    }
}

function wait-command($minutes = $sleepMinutes, $timer = $startTimer) {
    write-host "$(get-date) timer: $(((get-date) - $timer).tostring())"
    write-host "$(get-date) sleeping $minutes minutes" -ForegroundColor green
    start-sleep -Seconds ($minutes * 60)
    write-host "$(get-date) resuming" -ForegroundColor green
    $timer = get-date
}
