﻿<#
.Synopsis
   Cmdlet used to change Idrac attribute using REDFISH API.

.DESCRIPTION
   Cmdlet used to change Idrac attribute using REDFISH API.

.PARAMETER Ip_Idrac

    Specifies the IpAddress of Remote system's Idrac.

.PARAMETER Credential

    Specifies the credentials for Idrac connection.

.PARAMETER Session

    Specifies the session generated by New-RacSession for Idrac connection.

.PARAMETER Attribute

    Specifies the attribute that has to be changed.

.PARAMETER Value

    Specifies the value for the attribute.

.EXAMPLE
    Set-RacManagerDellAttribute -Ip_Idrac 10.2.160.84 -Credential $Cred -Attribute 'ServerPwr.1.RapidOnPrimaryPSU' -Value 'PSU2'

    This example set the PSU2 as primary PSU

.EXAMPLE
    Set-RacManagerDellAttribute -Ip_Idrac 10.2.160.84 -Credential $Cred -Attribute 'USBFront.1.Enable' -Value 'Enabled'

    This example enable Front Ports/Set Front USB Port Setting

.EXAMPLE
    Set-RacManagerDellAttribute -Ip_Idrac 10.2.160.84 -Credential $Cred -Attribute 'QuickSync.1.WifiEnable' -Value 'Enabled'

    This example enable QuickSync.1.WifiEnable


.LINK


#>


Function Set-RacManagerDellAttribute {
    [CmdletBinding(DefaultParameterSetName = 'Host')]
    param(
        [Parameter(ParameterSetName = 'Ip', Mandatory = $true, Position = 0)]
        [Alias("idrac_ip")]
        [ValidateNotNullOrEmpty()]
        [IpAddress]$Ip_Idrac,

        [Parameter(ParameterSetName = 'Host', Mandatory = $true, Position = 0)]
        [Alias("Server")]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname,

        [Parameter(ParameterSetName = 'Ip', Mandatory = $true, Position = 1)]
        [Parameter(ParameterSetName = 'Host', Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [pscredential]$Credential,

        [Parameter(ParameterSetName = 'Session', Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Session,
        
        [Parameter(Mandatory = $true)]
        [string]$Attribute,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Switch]$NoProxy
    )

    If ($PSBoundParameters['Hostname']) {
        $Ip_Idrac = [system.net.dns]::Resolve($Hostname).AddressList.IPAddressToString
    }

    Switch ($PsCmdlet.ParameterSetName) {
        Session {
            Write-Verbose -Message "Entering Session ParameterSet"
            $WebRequestParameter = @{
                Headers = $Session.Headers
                Method  = 'Get'
            }
            $Ip_Idrac = $Session.IPAddress
        }
        Default {
            Write-Verbose -Message "Entering Credentials ParameterSet"
            $WebRequestParameter = @{
                Headers     = @{"Accept" = "application/json" }
                Credential  = $Credential
                Method      = 'Get'
                ContentType = 'application/json'
            }
        }
    }

    If (! $NoProxy) { Set-myProxyAsDefault -Uri "Https://$Ip_Idrac" | Out-null }
    Else {
        Write-Verbose "No proxy requested"
        $Proxy = [System.Net.WebProxy]::new()
        $WebSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
        $WebSession.Proxy = $Proxy
        $WebRequestParameter.WebSession = $WebSession
        If ($PSVersionTable.PSVersion.Major -gt 5) { $WebRequestParameter.SkipCertificateCheck = $true }
    }

    # Change Password for User specified
    $JsonBody = @{
        "Attributes" = @{
            $Attribute = $Value
        }
    } | ConvertTo-Json -Compress

    # Built User list to get user's Id
    $PatchUri = "https://$Ip_Idrac/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellAttributes/System.Embedded.1"
    $WebRequestParameter.Uri = $PatchUri
    $WebRequestParameter.Body = $JsonBody
    $PatchResult = Invoke-RestMethod @WebRequestParameter


    $WebRequestParameter.Method = 'Get'
    $WebRequestParameter.Remove('Body')
    $GetResult = Invoke-RestMethod @WebRequestParameter
    $GetResult.Attributes | Select-Object $Attribute
}


Export-ModuleMember Set-RacManagerDellAttribute