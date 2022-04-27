# sf-ps1

## Overview
sf-ps1 is a powershell script manager inside a stateless service fabric application. sf-ps1 contains scripts only and has no dependencies.

by default, the script will send a Send-ServiceFabricNodeHealthReport every minute with statistics as shown below. If a warning or error pipelines are populated, the healthreport will be sent with a warning or error.

optionally using FabricDCA, an azure storage account can be used for output file upload and storage using 'sf_ps1_storageKey' and 'sf_ps1_storageEnabled' variables. Populate 'sf_ps1_storageKey' with the storage account 'Access keys'->'Connection string'

NOTE: do not add 'EndpointSuffix' attribute

### Example cloud.xml application parameters file

```xml
<?xml version="1.0" encoding="utf-8"?>
<Application Name="fabric:/sf_ps1" xmlns="http://schemas.microsoft.com/2011/01/fabric" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Parameters>
    <Parameter Name="sf_ps1_scripts" Value=".\sf-netstat.ps1;.\sf-console-graph.ps1" />
    <Parameter Name="sf_ps1_instanceCount" Value="-1" />
    <Parameter Name="sf_ps1_storageKey" Value="DefaultEndpointsProtocol=https;AccountName={{storage account}};AccountKey={{storage account key}}" />
    <Parameter Name="sf_ps1_storageEnabled" Value="false" />
  </Parameters>
</Application>
```

### Example health events in Service Fabric Console (SFX)
example script to warn on more than 900 fabricgateway connections  
script will error on 1000 or more fabricgateway connections  

![](media/sfx.1.png)

![](media/sfx.2.png)

![](media/sfx.3.png)

![](media/sfx.4.png)