###########################
# sf-ps1 etw wcmsvc script
# 
###########################
[cmdletbinding()]
param(
    [int]$sleepMinutes = ($env:sleepMinutes, 5 -ne $null)[0],
    [bool]$continuous = ($env:continuous, $false -ne $null)[0],
    [string]$outputFilePattern = ($env:outputFilePattern, "*sf_ps1_*.etl" -ne $null)[0],
    [string]$outputFileDestination = ($env:outputFileDestination, "..\log" -ne $null)[0],
    [int]$maxSizeMb = ($env:maxSize, 1024 -ne $null)[0],
    [string]$sessionName = "sf_ps1_wcm_Session",
    [string]$outputFile = ".\sf_ps1_wcm.etl",
    [string]$mode = 'Circular',
    [int]$buffSize = 1024,
    [int]$numBuffers = 16,
    [string]$keywords = '0xffffffffffffffff',
    [string[]]$etwProviders = @(
        '{988CE33B-DDE5-44EB-9816-EE156B443FF1}',
        'Microsoft-Windows-Wcmsvc',
        '{0616F7DD-722A-4DF1-B87A-414FA870D8B7}',
        'Microsoft-Windows-DNS-Client'
    )
)

set-location $psscriptroot
.\_sf-etw.ps1 @PSBoundParameters