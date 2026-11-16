$ErrorActionPreference='Stop'
# Managed model ONLY. No P/Invoke, no SCM mutation, no production integration.
Add-Type -Path @((Join-Path $PSScriptRoot 'ServiceIdentityObservationModel.cs'),(Join-Path $PSScriptRoot 'ServiceIdentityObservationTests.cs'))
if([PortableVBox.ServiceIdentityModel.ServiceIdentityObservationTests]::Main() -ne 0){throw 'Service identity model failed'}
