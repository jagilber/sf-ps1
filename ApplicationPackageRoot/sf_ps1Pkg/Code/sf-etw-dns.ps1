###########################
# sf-ps1 etw dns script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 5 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [bool]$format = $true,
    [string]$outputFilePattern = ($env:outputFilePattern, "*sf_ps1_etw_dns*.etl" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0],
    [string]$sessionName = "sf_ps1_etw_dns",
    [string]$outputFile = ".\sf_ps1_etw_dns.etl",
    [ValidateSet('circular', 'newfile')]
    [string]$mode = 'circular',
    [int]$buffSize = 1024,
    [int]$numBuffers = 16,
    [string]$keywords = '0xffffffffffffffff',
    [string[]]$etwProviders = @(
        'Microsoft-Windows-DNS-Client'
    )
)

$errorActionPreference = 'continue'
set-location $psscriptroot

foreach ($localP in $MyInvocation.MyCommand.Parameters.Keys) {
    if (!$PSBoundParameters.ContainsKey($localP) -and (Get-Variable -Name $localP -ValueOnly)) {
        $PSBoundParameters.Add($localP, (Get-Variable -Name $localP -ValueOnly))
    }        
}

.\_sf-etw.ps1 @PSBoundParameters