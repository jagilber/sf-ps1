# powershell test http listener for troubleshooting
# do a final client connect to free up close
[cmdletbinding()]
param(
    [int]$port = 80,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [switch]$server,
    [hashtable]$clientHeaders = @{ },
    [string]$clientBody = 'test message from client',
    [ValidateSet('GET', 'POST', 'HEAD')]
    [string]$clientMethod = "GET",
    [string]$absolutePath = '/'
)

$uri = "http://$($hostname):$port$absolutePath"
$http = $null
$scriptParams = $PSBoundParameters

function main() {
    try {
        if (!$server) {
            start-client
        }
        else {
            # start as job so server can exit gracefully after 2 minutes of cancellation
            #if ($host.Name -ine "ServerRemoteHost") {
            if ($false) {
                # called on foreground thread only
                start-job -ScriptBlock { param($script, $params); . $script @params } -ArgumentList $MyInvocation.ScriptName, $scriptParams

                while (get-job) {
                    foreach ($job in get-job) {
                        $jobInfo = Receive-Job -Job $job | convertto-json -Depth 5
                        if ($jobInfo) { write-host $jobInfo }
                        if ($job.State -ine "running") {
                            Remove-Job -Job $job -Force
                        }
                    }
                    start-sleep -Seconds 1
                }
    
            }
            else {
                start-server
            }
        }

        Write-Host "$(get-date) Finished!";
    }
    finally {
        Get-Job | Remove-job -Force
        if ($http) {
            $http.Stop()
            $http.Close()
            $http.Dispose();
        }
    }
}

function start-client([hashtable]$header = $clientHeaders, [string]$body = $clientBody, [string]$method = $clientMethod, [string]$clientUri = $uri) {
    $iteration = 0

    while ($iteration -lt $count -or $count -eq 0) {
        try {
            $requestId = [guid]::NewGuid().ToString()
            write-verbose "request id: $requestId"
            if ($header.Count -lt 1) {
                $header = @{
                    'accept'                 = 'application/json'
                    #'authorization'          = "Bearer $(Token)"
                    'content-type'           = 'text/html' #'application/json'
                    'client'                 = $env:COMPUTERNAME
                    'host'                   = $hostName
                    'x-ms-app'               = [io.path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
                    'x-ms-user'              = $env:USERNAME
                    'x-ms-client-request-id' = $requestId
                } 
            }

            $params = @{
                method  = $method
                uri     = $uri
                headers = $header
            }
        
            if ($method -ieq 'POST' -and ![string]::IsNullOrEmpty($body)) {
                $params += @{body = $body }
            }
            write-verbose ($header | convertto-json)
            Write-Verbose ($params | fl * | out-string)
    
            $error.clear()
            $result = Invoke-WebRequest -verbose @params
            write-host $result 
        
            if ($error) {
                write-host "$($error | out-string)"
                $error.Clear()
            }
        }
        catch {
            Write-Warning "exception reading from server`r`n$($_)"
        }

        start-sleep -Seconds 1
        $iteration++
    }
}

function start-server() {
    $iteration = 0
    $http = [net.httpListener]::new();
    $http.Prefixes.Add("http://$(hostname):$port/")
    $http.Prefixes.Add("http://*:$port/")
    $http.Start();
    $maxBuffer = 1024

    if ($http.IsListening) {
        write-host "http server listening. max buffer $maxBuffer"
        write-host "navigate to $($http.Prefixes)" -ForegroundColor Yellow
    }

    while ($iteration -lt $count -or $count -eq 0) {
        try {
            $context = $http.GetContext()
            [hashtable]$requestHeaders = @{ }
            [string]$requestHeadersString = ""

            foreach ($header in $context.Request.Headers.AllKeys) {
                $requestHeaders.Add($header, @($context.Request.Headers.GetValues($header)))
                $requestHeadersString += "$($header):$(($context.Request.Headers.GetValues($header)) -join ';'),"
            }

            [string]$html = $null
            write-host "$(get-date) http server $($context.Request.UserHostAddress) received $($context.Request.HttpMethod) request:`r`n"

            if ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/') {
                write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                $html += "`r`nREQUEST HEADERS:`r`n$($requestHeaders | out-string)`r`n"
                $html += $context | ConvertTo-Json -depth 99
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq '/min') {
                write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                $html += "`r`nREQUEST HEADERS:`r`n$($requestHeaders | out-string)`r`n"
            }
            elseif ($context.Request.HttpMethod -eq 'GET' -and $context.Request.RawUrl -eq $absolutePath) {
                write-host "$(get-date) $($context.Request.UserHostAddress)  =>  $($context.Request.Url)" -ForegroundColor Magenta
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                $html += $context | ConvertTo-Json -depth 99
            }
            elseif ($context.Request.HttpMethod -eq 'POST' -and $context.Request.RawUrl -eq '/') {
                $html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
                [byte[]]$inputBuffer = @(0) * $maxBuffer
                $context.Request.InputStream.Read($inputBuffer, 0, $maxBuffer)# $context.Request.InputStream.Length)
                $html += "INPUT STREAM: $(([text.encoding]::ASCII.GetString($inputBuffer)).Trim())`r`n"
                $html += $context | ConvertTo-Json -depth 99
            }
            else {
                #$html = "$(get-date) http server $($env:computername) received $($context.Request.HttpMethod) request:`r`n"
            }

            if ($html) {
                write-host $html
                #respond to the request
                $buffer = [Text.Encoding]::ASCII.GetBytes($html)
                $context.Response.ContentLength64 = $buffer.Length
                $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
                $context.Response.OutputStream.Close()
            }
            else {
                # head
                $context.Response.Headers.Add("requestHeaders", $requestHeadersString)    
                $context.Response.OutputStream.Close()
            }
        
            $iteration++
        }
        catch {
            Write-Warning "error $($_)"
        }
    }
}

main