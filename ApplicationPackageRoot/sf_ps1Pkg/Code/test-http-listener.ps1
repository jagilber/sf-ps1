# powershell test http listener for troubleshooting
# do a final client connect to free up close
[cmdletbinding()]
param(
    [int]$port = 80,
    [int]$count = 0,
    [string]$hostName = 'localhost',
    [bool]$server,
    [hashtable]$clientHeaders = @{ },
    [string]$clientBody = 'test message from client',
    [ValidateSet('GET', 'POST', 'HEAD')]
    [string]$clientMethod = "GET",
    [string]$absolutePath = '/',
    [string]$proxy = "", #"http://localhost:$($port + 1)/",
    [bool]$useClientProxy
)

$uri = "http://$($hostname):$port$absolutePath"
$http = $null
$scriptParams = $PSBoundParameters
$httpClient = $null
$httpClientHandler = $null

function main() {
    try {
        if (!$server) {
            #start-client
            start-httpClient
        }
        else {
            # start as job so server can exit gracefully after 2 minutes of cancellation
            if ($host.Name -ine "ServerRemoteHost") {
                #if ($false) {
                # called on foreground thread only
                start-server -asjob
            }
            else {
                start-server
            }
        }

        Write-Host "$(get-date) Finished!";
    }
    finally {
        Get-Job | Remove-job -Force
        if ($httpClientHandler) {
            $httpClientHandler.Dispose()
        }
        if ($http) {
            $http.Stop()
            $http.Close()
            $http.Dispose();
        }
    }
}

function start-httpClient([hashtable]$header = $clientHeaders, [string]$body = $clientBody, [net.http.httpMethod]$method = $clientMethod, [string]$clientUri = $uri) {
    $iteration = 0
    $httpClientHandler = new-object net.http.HttpClientHandler

    if($proxy) {
        $proxyPort = $port++
        if($useClientProxy) {
        start-server -asjob -serverPort $proxyPort
        }
        $httpClientHandler.UseProxy = $true
        $httpClientHandler.Proxy = new-object net.webproxy("http://localhost:$proxyPort/",$false)
    }

    $httpClient = New-Object net.http.httpClient($httpClientHandler)


    while ($iteration -lt $count -or $count -eq 0) {
        try {
            $requestId = [guid]::NewGuid().ToString()
            write-verbose "request id: $requestId"
            $requestMessage = new-object net.http.httpRequestMessage($method, $clientUri )
           # $responseMessage = new-object net.http.httpResponseMessage

            if($method -ine [net.http.httpMethod]::Get) {
                $httpContent = new-object net.http.stringContent([string]::Empty,[text.encoding]::ascii,'text/html')
                $requestMessage.Content = $httpContent
            }
            else {
                $httpContent = new-object net.http.stringContent([string]::Empty,[text.encoding]::ascii,'text/html')
                #$responseMessage.Content = $httpContent
            }

            if ($header.Count -lt 1) {
                $requestMessage.Headers.Accept.TryParseAdd('application/json')
                $requestMessage.Headers.Add('client',$env:COMPUTERNAME)
                #$requestMessage.Headers.Add('host',$hostname)
                $requestMessage.Headers.Add('x-ms-app', [io.path]::GetFileNameWithoutExtension($MyInvocation.ScriptName))
                $requestMessage.Headers.Add('x-ms-user', $env:USERNAME)
                $requestMessage.Headers.Add('x-ms-client-request-id', $requestId)
            }

            #$response = $httpClient.GetAsync($clientUri, 1).Result #
            #$response = $httpClient.PostAsync($clientUri,$httpContent).Result # works but no content in response
            $response = $httpClient.SendAsync($requestMessage, 1).Result # works but no content in response
            #write-host ($httpClient | fl * | convertto-json -Depth 99)
            #$requestMessage.
            $httpClient
            $response
            $response.Content | convertto-json
            $response.Content.ReadAsStringAsync().Result 
        #    pause
        
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

function start-client([hashtable]$header = $clientHeaders, [string]$body = $clientBody, [net.http.httpMethod]$method = $clientMethod, [string]$clientUri = $uri) {
    $iteration = 0
    
    if ($useClientProxy) {
        $proxyPort = $port++
        start-server -asjob -serverPort $proxyPort -return
        #$proxy = new-object net.webproxy("http://localhost:$proxyPort/", $false)
        $proxy = "http://localhost:$proxyPort/"
    }

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
                method  = $method.Method
                uri     = $uri
                headers = $header
            }
        
            if ($method -ieq 'POST' -and ![string]::IsNullOrEmpty($body)) {
                $params += @{body = $body }
            }
            if ($proxy) {
                $params += @{proxy = $proxy }
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

function start-server([switch]$asjob, [int]$serverPort = $port, [switch]$return) {

    if ($asjob) {
        [void]$scriptParams.Remove('server')
        [void]$scriptParams.Add('server',$true)
        [void]$scriptParams.Remove('useClientProxy')
        start-job -ScriptBlock { param($script, $params); . $script @params } -ArgumentList $MyInvocation.ScriptName, $scriptParams

        while (get-job) {
            foreach ($parentjob in get-job) {
                foreach($job in $parentjob) {
                    $jobInfo = Receive-Job -Job $job | convertto-json -Depth 5
                    if ($jobInfo) { write-host $jobInfo }
                    if ($job.State -ine "running" -and $job.State -ine "NotStarted") {
                        Remove-Job -Job $job -Force
                    }
                    elseif($return) {
                        return
                    }
                }
            }
            start-sleep -Seconds 1
        }

    }

    $iteration = 0
    $http = [net.httpListener]::new();
    $http.Prefixes.Add("http://$(hostname):$serverPort/")
    $http.Prefixes.Add("http://*:$serverPort/")
    $http.Prefixes.Add("http://localhost:$serverPort/")
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