﻿<#

.DESCRIPTION

Ce script permet de configurer les cartes idrac9 intégrées sur les serveurs DELL

.PARAMETER Ip_Idrac

    Specifies the IpAddress of Remote system's Idrac.

.PARAMETER Credential

    Specifies the credentials for Idrac connection.

.PARAMETER Session

    Specifies the session generated by New-RacSession for Idrac connection.

.PARAMETER User

    Specifies the username of the privileged local account to create in place of root.

.PARAMETER Password

    Specifies the current password of the privileged local account, usualy root.

.PARAMETER NewPassword

    Specifies the new password of the privileged local account whether you would like to change it.

.PARAMETER Hostname

    Specifies the full qualified domain name of the idrac interface.

.PARAMETER StaticIpAddress

    Specifies the static ip address of the idrac interface whether the current one has to be changed.

.PARAMETER PrefixLength

    Specifies the PrefixLength of the subnet mask of the idrac interface.

.PARAMETER NextHop

    Specifies the gateway of the idrac interface.

.PARAMETER PrimaryDns

    Specifies primary dns address of the idrac interface.

.PARAMETER SecondaryDns

    Specifies secondary dns address of the idrac interface.

.EXAMPLE

New-RacTemplate -TemplatePath C:\temp\Idrac9_Template.xml -IpAddress 10.111.1.102 -Hostname idrac-panutaflax155.idrac.boursorama.fr

Note: le mot de passe sécurisé est indiqué en face avant du serveur (étiquette "IDRAC Default Password").

.EXAMPLE

New-RacTemplate -TemplatePath C:\temp\Idrac9_Template.xml -IpAddress 10.111.1.102 -Hostname idrac-panutaflax155.idrac.boursorama.fr -User root -Password calvin -NewPassword NewSecurePassword:! -PrimaryDns 10.4.2.2 -SecondaryDns 10.4.1.2

.EXAMPLE

New-RacTemplate -TemplatePath C:\temp\Idrac9_Template.xml -IpAddress 10.111.1.102 -Hostname idrac-panutaflax155.idrac.boursorama.fr -User root -Password calvin -NewPassword NewSecurePassword:! -StaticIpAddress 10.111.1.102 -PrefixLength 24 -NextHop 10.111.1.254 -PrimaryDns 10.4.2.2 -SecondaryDns 10.4.1.2

.NOTES

Date: 28/09/2023


#>

Function New-RacTemplate {
    [CmdletBinding(DefaultParameterSetName = 'DHCP')]
    Param(
        [Parameter(mandatory=$true, HelpMessage="Path to template." )]
        [ValidateScript({
            if(-Not ($_ | Test-Path) ){
                throw "File or folder does not exist" 
            }
            if(-Not ($_ | Test-Path -PathType Leaf) ){
                throw "The Path argument must be a file. Folder paths are not allowed."
            }
                return $true
        })]
        [Alias("SP", "FilePath")]
        [string]$SourcePath,

        [Parameter(mandatory=$false, HelpMessage="Current Ip Address.")]
        [Alias("Ip")]
        [string]$IpAddress,

        [Parameter(mandatory=$false, HelpMessage="Idrac power user, default is root")]
        [string]$User = 'root',

        [Parameter(mandatory=$false, HelpMessage="New password, get it in Securden.")]
        [SecureString]$NewPassword,

        [Parameter(Mandatory=$false, HelpMessage="Idrac fqdn wether it's not declared in DNS yet.")]
        [ValidatePattern("idrac-\w+\.idrac.boursorama.fr")]
        [string]$Hostname, 

        [Parameter(mandatory=$true, ParameterSetName = 'StaticIp', HelpMessage="Static Ip Address pushed with the template.")]
        [string]$StaticIpAddress,

        [Parameter(mandatory=$false, ParameterSetName = 'StaticIp', HelpMessage="Gateway pushed with the template.")]
        [Alias("GW")]
        [string]$NextHop,
        
        [Parameter(mandatory=$true, ParameterSetName = 'StaticIp', HelpMessage="Prefix Length aka bit mask format.")]
        [Alias("PL")]
        [string]$PrefixLength,
        
        [Parameter(mandatory=$false, ParameterSetName = 'StaticIp', HelpMessage="Primary DNS Address.")]
        [Alias("DNS1")]
        [string]$PrimaryDns = "10.4.2.2" ,
        
        [Parameter(mandatory=$false, ParameterSetName = 'StaticIp', HelpMessage="Secondary DNS Address.")]
        [Alias("DNS2")]
        [string]$SecondaryDns = "10.4.1.2"
    )

    Filter ConvertTo-BinaryFromLength { ("1" * $_).PadRight(32, "0") }
    Filter ConvertTo-IPFromBinary { ([System.Net.IPAddress]"$([System.Convert]::ToInt64($_,2))").IPAddressToString }

    $Bilan = [PsCustomObject]::new()

  # Guessing algo: Hostname
    If ([String]::IsNullOrEmpty($Hostname)) { 
        Try {
            $Hostname = [System.Net.Dns]::GetHostEntry($IpAddress).HostName.ToLower()
            Write-Host "Hostname is not specified, I assume it's $Hostname" -ForegroundColor Yellow
            $Bilan.psobject.Members.Add([psnoteproperty]::new('Hostname', $Hostname))
        } Catch {
            Throw "$IpAddress cannot be resolved, please use -Hostname parameter."
        }
    } Else {
        $Hostname = $Hostname.ToLower()
        Write-Host "Hostname is specified: $Hostname" -ForegroundColor Yellow
    }
    

  # Guessing algo: Current Ip
    If ([string]::IsNullOrEmpty($IpAddress)) {
        If ($PSBoundParameters.Keys -eq 'StaticIpAddress') {
            Write-Host "IpAddress is not specified, I assume it's $StaticIpAddress." -ForegroundColor Yellow
            $IpAddress = $StaticIpAddress
        } Else {
            If ($PSBoundParameters.Keys -eq 'Hostname') {
                Write-Host "IpAdress and StaticIpAddress are not specified, Trying to get IpAddress from $Hostname resolution." -ForegroundColor Yellow -NoNewline
                Try {
                    $HostEntry = [System.Net.Dns]::GetHostEntry($Hostname)
                    $IpAddress = $HostEntry.AddressList.IPAddressToString
                    Write-Host "Found -> $IpAddress" -ForegroundColor Yellow
                } Catch {
                    Throw "$Hostname cannot be resolved, please use -IpAddress parameter."
                }
            }
        }
    }

  # Guessing algo: NextHop
    If ([string]::IsNullOrEmpty($NextHop) -and (-not [string]::IsNullOrEmpty($StaticIpAddress))) { 
        $NextHop = Get-LastValidIp "$StaticIpAddress/$PrefixLength"
        Write-Host "NextHop is not specified, I assume it's $NextHop." -ForegroundColor Yellow
    }

    Try {
        If (-not [String]::IsNullOrEmpty($NewPassword)) {
            $NewPasswd = ConvertFrom-SecureString $NewPassword -ea Stop
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewPassword)
            $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        }
        Else {
            Write-Host "NewPassword cannot be null"
        }
    } Catch {
        throw $_
    }
     
    Write-Host "Starting correction of the template $([System.Io.Path]::GetFileName($SourcePath)): " -NoNewline
    Try {
        $ManualDNSEntry = "$IpAddress,$Hostname"

        $xml = [xml](Get-Content -Path $SourcePath)
        $xmlUserName = $xml.SelectSingleNode("//Attribute[@Name='Users.2#UserName']")
        If ($PSBoundParameters.Keys -eq 'User') { 
            $xmlUserName.InnerText = $User
            $Bilan.psobject.Members.Add([psnoteproperty]::new('User', $User))

        }
        Else { 
            [void]$xmlUserName.ParentNode.RemoveChild($xmlUserName)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('User', '*No Change*'))
        }

        $xmlPassWord = $xml.SelectSingleNode("//Attribute[@Name='Users.2#Password']")
        If ($PSBoundParameters.Keys -eq 'NewPassword') {
            $xmlPassWord.InnerText = $UnsecurePassword
            $PartialPwd = $UnsecurePassword.Replace($UnsecurePassword.Substring(1,$UnsecurePassword.Length -2), "."*($UnsecurePassword.Length -2))
            $Bilan.psobject.Members.Add([psnoteproperty]::new('Password', $PartialPwd))
        }
        Else { 
            [void]$xmlPassWord.ParentNode.RemoveChild($xmlPassWord)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('Password', '*No Change*'))
        }


        $xmlManualDNSEntry = $xml.SelectSingleNode("//Attribute[@Name='WebServer.1#ManualDNSEntry']")
        $xmlManualDNSEntry.InnerText = $ManualDNSEntry
        $Bilan.psobject.Members.Add([psnoteproperty]::new('ManualDNSEntry', $ManualDNSEntry))

        $xmlRacName = $xml.SelectSingleNode("//Attribute[@Name='ActiveDirectory.1#RacName']")
        $xmlRacName.InnerText = $Hostname.Split('.')[0]
        $Bilan.psobject.Members.Add([psnoteproperty]::new('RacName', $Hostname.Split('.')[0]))


        $xmlRacName = $xml.SelectSingleNode("//Attribute[@Name='NIC.1#DNSRacName']")
        $xmlRacName.InnerText = $Hostname.Split('.')[0]
        $Bilan.psobject.Members.Add([psnoteproperty]::new('DNSRacName', $Hostname.Split('.')[0]))


        $xmlAddress = $xml.SelectSingleNode("//Attribute[@Name='IPv4Static.1#Address']")
        $xmlNetMask = $xml.SelectSingleNode("//Attribute[@Name='IPv4Static.1#Netmask']")
        $xmlGateway = $xml.SelectSingleNode("//Attribute[@Name='IPv4Static.1#Gateway']")
        $xmlDNS1 = $xml.SelectSingleNode("//Attribute[@Name='IPv4Static.1#DNS1']")
        $xmlDNS2 = $xml.SelectSingleNode("//Attribute[@Name='IPv4Static.1#DNS2']")
        $xmlDHCPEnable = $xml.SelectSingleNode("//Attribute[@Name='IPv4.1#DHCPEnable']")

        If (-not [string]::IsNullOrEmpty($StaticIpAddress)) {
            $xmlDHCPEnable.InnerText = 'Disabled'
            $Bilan.psobject.Members.Add([psnoteproperty]::new('DHCPEnable', 'Disabled'))

            $xmlAddress.InnerText = $StaticIpAddress
            $Bilan.psobject.Members.Add([psnoteproperty]::new('StaticIpAddress', $StaticIpAddress))
        }
        Else { 
            [void]$xmlAddress.ParentNode.RemoveChild($xmlAddress)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('StaticIpAddress', '*No Change*'))
          
          # Si pas d'adresse IP statique demandée alors on ne touche pas au DHCP.
            [void]$xmlDHCPEnable.ParentNode.RemoveChild($xmlDHCPEnable)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('DHCPEnable', '*No Change*'))
        }

        If (-not [string]::IsNullOrEmpty($PrefixLength)) { 
            $NetMask = $PrefixLength | ConvertTo-BinaryFromLength | ConvertTo-IPFromBinary
            $xmlNetMask.InnerText = $NetMask
            $Bilan.psobject.Members.Add([psnoteproperty]::new('NetMask', $NetMask))
        } 
        Else { 
            [void]$xmlNetMask.ParentNode.RemoveChild($xmlNetMask)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('NetMask', '*No Change*'))
        }


        If (-not [string]::IsNullOrEmpty($NextHop)) { 
            $xmlGateway.InnerText = $NextHop
            $Bilan.psobject.Members.Add([psnoteproperty]::new('Gateway', $NextHop))
        }
        Else {
            [void]$xmlGateway.ParentNode.RemoveChild($xmlGateway)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('Gateway', '*No Change*'))
        }

        If (-not [string]::IsNullOrEmpty($PrimaryDns)) { 
            $xmlDNS1.InnerText = $PrimaryDns
            $Bilan.psobject.Members.Add([psnoteproperty]::new('PrimaryDns', $PrimaryDns))
        }
        Else {
            [void]$xmlDNS1.ParentNode.RemoveChild($xmlDNS1)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('PrimaryDns', '*No Change*'))
        }

        If (-not [string]::IsNullOrEmpty($SecondaryDns)) {
            $xmlDNS2.InnerText = $SecondaryDns
            $Bilan.psobject.Members.Add([psnoteproperty]::new('SecondaryDns', $SecondaryDns))
        }
        Else {
            [void]$xmlDNS2.ParentNode.RemoveChild($xmlDNS2)
            $Bilan.psobject.Members.Add([psnoteproperty]::new('SecondaryDns', '*No Change*'))
        }


        # Boom !
        $TargetPath = [System.Io.Path]::Combine([System.Io.Path]::GetDirectoryName($SourcePath),[System.Io.Path]::GetFileNameWithoutExtension($SourcePath) + "_$($Hostname.Split('.')[0])" + [System.Io.Path]::GetExtension($SourcePath))
        $xml.Save($TargetPath)

        $Bilan | Show-menu -Title "Résumé des changements"

        Return $TargetPath

    } Catch {
        Throw $_
    }

}

Export-ModuleMember Set-RacTemplate

