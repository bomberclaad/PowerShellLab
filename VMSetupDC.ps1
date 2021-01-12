<#
 .DESCRIPTION
    Setup Domain Controller
 .NOTES
    AUTHOR Jonas Henriksson
 .LINK
    https://github.com/bomberclaad
#>

[cmdletbinding(SupportsShouldProcess=$true)]

Param
(
    # VM name
    [String]$VMName,
    # Computer name
    [String]$ComputerName,

    # Serializable parameters
    $Session,
    $Credential,

    # Type of DC
    #[Parameter(Mandatory=$true)]
    [ValidateSet('ADDSForest')]
    [String]$DCType = 'ADDSForest',

    # Name of domain to setup
    [Parameter(Mandatory=$true)]
    [String]$DomainName,

    # Netbios name of domain to setup
    [Parameter(Mandatory=$true)]
    [String]$DomainNetbiosName,

    # Network Id
    [Parameter(Mandatory=$true)]
    [String]$DomainNetworkId,

    # Local admin password on domain controller
    [Parameter(Mandatory=$true)]
    $DomainLocalPassword,

    # DNS
    [String]$DNSReverseLookupZone,
    [TimeSpan]$DNSRefreshInterval,
    [TimeSpan]$DNSNoRefreshInterval,
    [TimeSpan]$DNSScavengingInterval,
    [Bool]$DNSScavengingState,

    # DHCP
    [String]$DHCPScope,
    [String]$DHCPScopeStartRange,
    [String]$DHCPScopeEndRange,
    [String]$DHCPScopeSubnetMask,
    [String]$DHCPScopeDefaultGateway,
    [Array]$DHCPScopeDNSServer,
    [String]$DHCPScopeLeaseDuration,

    # Path to gpos
    [String]$BaselinePath,
    [String]$GPOPath,
    [String]$TemplatePath,

    # Switches
    [Switch]$BackupGpo,
    [Switch]$BackupTemplates
)

Begin
{
    # ██████╗ ███████╗ ██████╗ ██╗███╗   ██╗
    # ██╔══██╗██╔════╝██╔════╝ ██║████╗  ██║
    # ██████╔╝█████╗  ██║  ███╗██║██╔██╗ ██║
    # ██╔══██╗██╔══╝  ██║   ██║██║██║╚██╗██║
    # ██████╔╝███████╗╚██████╔╝██║██║ ╚████║
    # ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝

    ##############
    # Deserialize
    ##############

    $Serializable =
    @(
        @{ Name = 'Session';                                      },
        @{ Name = 'Credential';             Type = [PSCredential] },
        @{ Name = 'DomainLocalPassword';    Type = [SecureString] },
        @{ Name = 'DHCPScopeDNSServer';     Type = [Array]        }
    )

    #########
    # Invoke
    #########

    Invoke-Command -ScriptBlock `
    {
        try
        {
            . $PSScriptRoot\s_Begin.ps1
            . $PSScriptRoot\f_ShouldProcess.ps1
        }
        catch [Exception]
        {
            throw $_
        }

    } -NoNewScope

    #################
    # Define presets
    #################

    $Preset =
    @{
        ADDSForest =
        @{
            # DNS
            DNSReverseLookupZone = (($DomainNetworkId -split '\.')[-1..-3] -join '.') + '.in-addr.arpa'
            DNSRefreshInterval = '7.00:00:00'
            DNSNoRefreshInterval = '7.00:00:00'
            DNSScavengingInterval = '0.07:00:00'
            DNSScavengingState = $true

            # DHCP
            DHCPScope = "$DomainNetworkId.0"
            DHCPScopeStartRange = "$DomainNetworkId.154"
            DHCPScopeEndRange = "$DomainNetworkId.254"
            DHCPScopeSubnetMask = '255.255.255.0'
            DHCPScopeDefaultGateway = "$DomainNetworkId.1"
            DHCPScopeDNSServer = @("$DomainNetworkId.10")
            DHCPScopeLeaseDuration = '14.00:00:00'
        }
    }

    # Set preset values for missing parameters
    foreach ($Var in $MyInvocation.MyCommand.Parameters.Keys)
    {
        if ($Preset.Item($DCType).ContainsKey($Var) -and
            -not (Get-Variable -Name $Var).Value)
        {
            Set-Variable -Name $Var -Value $Preset.Item($DCType).Item($Var)
        }
    }

    ##################
    # Copy to session
    ##################

    if ($Session)
    {
        $DCTemp = Invoke-Command -Session $Session -ScriptBlock {

            Write-Output -InputObject $env:TEMP
        }

        $Paths =
        @(
            @{ Name = 'Gpos';                   Source = $GpoPath;       Destination = "$DCTemp\Gpo" }
            @{ Name = 'Baseline gpos';          Source = $BaselinePath;  Destination = "$DCTemp\Baseline" }
            @{ Name = 'Certificate templates';  Source = $TemplatePath;  Destination = "$DCTemp\Templates" }
        )

        foreach ($Path in $Paths)
        {
            # Check if source exist
            if ($Path.Source -and (Test-Path -Path $Path.Source) -and
                (ShouldProcess @WhatIfSplat -Message "Copying `"$($Path.Name)`" to `"$($Path.Destination)`"." @VerboseSplat))
            {
                Copy-Item -ToSession $Session -Path $Path.Source -Destination $Path.Destination -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # ███╗   ███╗ █████╗ ██╗███╗   ██╗
    # ████╗ ████║██╔══██╗██║████╗  ██║
    # ██╔████╔██║███████║██║██╔██╗ ██║
    # ██║╚██╔╝██║██╔══██║██║██║╚██╗██║
    # ██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
    # ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝

    $MainScriptBlock =
    {
        # Get base DN
        $BaseDN = Get-BaseDn -DomainName $DomainName

        # Set friendly netbios name
        $DomainPrefix = $DomainNetbiosName.Substring(0, 1).ToUpper() + $DomainNetbiosName.Substring(1)

        # ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗
        # ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║
        # ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║
        # ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║
        # ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
        # ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝

        # Check if RSAT-ADCS-Mgmt is installed
        if (((Get-WindowsFeature -Name RSAT-ADCS-Mgmt).InstallState -notmatch 'Install') -and
            (ShouldProcess @WhatIfSplat -Message "Installing RSAT-ADCS-Mgmt feature." @VerboseSplat))
        {
            Install-WindowsFeature -Name RSAT-ADCS-Mgmt > $null
        }

        # Check if DHCP windows feature is installed
        if (((Get-WindowsFeature -Name DHCP).InstallState -notmatch 'Install') -and
            (ShouldProcess @WhatIfSplat -Message "Installing DHCP windows feature." @VerboseSplat))
        {
            Install-WindowsFeature -Name DHCP -IncludeManagementTools > $null
        }

        # Check if ADDS feature is installed
        if (((Get-WindowsFeature -Name AD-Domain-Services).InstallState -notmatch 'Install') -and
            (ShouldProcess @WhatIfSplat -Message "Installing AD-Domain-Services feature." @VerboseSplat))
        {
            Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools > $null
        }

        # Check if ADDS is installed
        if (-not (Test-Path -Path "$env:SystemRoot\SYSVOL" -ErrorAction SilentlyContinue) -and
           (ShouldProcess @WhatIfSplat -Message "Installing ADDS forest." @VerboseSplat))
        {
            Install-ADDSForest -DomainName $DomainName `
                               -DomainNetbiosName $DomainNetbiosName `
                               -SafeModeAdministratorPassword $DomainLocalPassword `
                               -Force > $null

            Write-Warning -Message "Rebooting `"$ComputerName`", rerun this script to continue setup."
            break
        }
        else
        {
            # ██████╗ ███╗   ██╗███████╗
            # ██╔══██╗████╗  ██║██╔════╝
            # ██║  ██║██╔██╗ ██║███████╗
            # ██║  ██║██║╚██╗██║╚════██║
            # ██████╔╝██║ ╚████║███████║
            # ╚═════╝ ╚═╝  ╚═══╝╚══════╝

            # Check if DNS server is installed and running
            if ((Get-Service -Name DNS -ErrorAction SilentlyContinue) -and (Get-Service -Name DNS).Status -eq 'Running')
            {
                #########
                # Server
                #########

                # Checking DNS server scavenging state
                if (((Get-DnsServerScavenging).ScavengingState -ne $DNSScavengingState) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server scavenging state to $DNSScavengingState." @VerboseSplat))
                {
                    Set-DnsServerScavenging -ScavengingState $DNSScavengingState -ApplyOnAllZones
                }

                # Checking DNS server refresh interval
                if (((Get-DnsServerScavenging).RefreshInterval -ne $DNSRefreshInterval) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server refresh interval to $DNSRefreshInterval." @VerboseSplat))
                {
                    Set-DnsServerScavenging -RefreshInterval $DNSRefreshInterval -ApplyOnAllZones
                }

                # Checking DNS server no refresh interval
                if (((Get-DnsServerScavenging).NoRefreshInterval -ne $DNSNoRefreshInterval) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server no refresh interval to $DNSNoRefreshInterval." @VerboseSplat))
                {
                    Set-DnsServerScavenging -NoRefreshInterval $DNSNoRefreshInterval -ApplyOnAllZones
                }

                # Checking DNS server scavenging interval
                if (((Get-DnsServerScavenging).ScavengingInterval -ne $DNSScavengingInterval) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DNS server scavenging interval to $DNSScavengingInterval." @VerboseSplat))
                {
                    Set-DnsServerScavenging -ScavengingInterval $DNSScavengingInterval -ApplyOnAllZones
                }

                ##########
                # Reverse
                ##########

                # Checking reverse lookup zone
                if (-not (Get-DnsServerZone -Name $DNSReverseLookupZone -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Adding DNS server reverse lookup zone `"$DNSReverseLookupZone`"." @VerboseSplat))
                {
                    Add-DnsServerPrimaryZone -Name $DNSReverseLookupZone -ReplicationScope Domain -DynamicUpdate Secure
                }

                ######
                # CAA
                ######

                # FIX
                # Check if "\# Length" is needed
                # Array of allowed CAs
                # Replace = Clone and add : https://docs.microsoft.com/en-us/powershell/module/dnsserver/set-dnsserverresourcerecord?view=win10-ps

                # Get CAA record
                $CAA = Get-DnsServerResourceRecord -ZoneName $DomainName -Name $DomainName -Type 257

                # RData with flag = 0, tag length = 5, tag = issue and value = $DomainName
                # See https://tools.ietf.org/html/rfc6844#section-5
                $RData = "00056973737565$($DomainName.ToCharArray().ToInt32($null).ForEach({ '{0:X}' -f $_ }) -join '')"

                # Checking CAA record
                if ((-not $CAA -or $CAA.RecordData.Data -ne $RData) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting `"$RData`" to CAA record." @VerboseSplat))
                {
                    Add-DnsServerResourceRecord -ZoneName $DomainName -Name $DomainName -Type 257 -RecordData $RData
                }

                ##########
                # Records
                ##########

                # Initialize
                $Server = @{}

                # Define server records to get
                $ServerNames = @('ADFS', 'AS', 'WAP')

                foreach ($Name in $ServerNames)
                {
                    # Get record
                    $ServerHostName = Get-DnsServerResourceRecord -ZoneName $DomainName -RRType A | Where-Object { $_.HostName -like "$Name*" -and $_.Timestamp -notlike $null } | Select-Object -ExpandProperty HostName -First 1

                    if ($ServerHostName)
                    {
                        $Server.Add($Name, $ServerHostName)
                    }
                }

                # Set records
                $DnsRecords =
                @(
                    @{ Name = 'wap';     Type = 'A';  Data = "$DomainNetworkId.100" }
                    @{ Name = 'adfs';    Type = 'A';  Data = "$DomainNetworkId.150" }
                )

                # Check if server exist
                if ($Server.AS)
                {
                    $DnsRecords += @{ Name = 'pki';  Type = 'CNAME';  Data = "$($Server.AS).$DomainName." }
                }

                foreach($Rec in $DnsRecords)
                {
                    $ResourceRecord = Get-DnsServerResourceRecord -ZoneName $DomainName -Name $Rec.Name -RRType $Rec.Type -ErrorAction SilentlyContinue

                    switch($Rec.Type)
                    {
                        'A'
                        {
                            $RecordType = @{ A = $true; IPv4Address = $Rec.Data; }
                            $RecordData = $ResourceRecord.RecordData.IPv4Address
                        }
                        'CNAME'
                        {
                            $RecordType = @{ CName = $true; HostNameAlias = $Rec.Data; }
                            $RecordData = $ResourceRecord.RecordData.HostnameAlias
                        }
                    }

                    if ($RecordData -ne $Rec.Data -and
                        (ShouldProcess @WhatIfSplat -Message "Adding $($Rec.Type) `"$($Rec.Name)`" -> `"$($Rec.Data)`"." @VerboseSplat))
                    {
                        Add-DnsServerResourceRecord -ZoneName $DomainName -Name $Rec.Name @RecordType
                    }
                }
            }

            # ██████╗ ██╗  ██╗ ██████╗██████╗
            # ██╔══██╗██║  ██║██╔════╝██╔══██╗
            # ██║  ██║███████║██║     ██████╔╝
            # ██║  ██║██╔══██║██║     ██╔═══╝
            # ██████╔╝██║  ██║╚██████╗██║
            # ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝

            # Check if DHCP server is installed and running
            if ((Get-Service -Name DHCPServer).Status -eq 'Running')
            {
                # Authorize DHCP server
                if ((Get-DhcpServerSetting).IsAuthorized -eq $false -and
                    (ShouldProcess @WhatIfSplat -Message "Authorizing DHCP server." @VerboseSplat))
                {
                    Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN"
                }

                # Dynamically update DNS
                if ((Get-DhcpServerv4DnsSetting).DynamicUpdates -ne 'Always' -and
                    (ShouldProcess @WhatIfSplat -Message "Enable always dynamically update DNS." @VerboseSplat))
                {
                    Set-DhcpServerv4DnsSetting -DynamicUpdates Always
                }

                # Scope
                if (-not (Get-DhcpServerv4Scope -ScopeId $DHCPScope -ErrorAction SilentlyContinue) -and
                    (ShouldProcess @WhatIfSplat -Message "Adding DHCP scope $DHCPScope ($DHCPScopeStartRange-$DHCPScopeEndRange/$DHCPScopeSubnetMask) with duration $DHCPScopeLeaseDuration" @VerboseSplat))
                {
                    Add-DhcpServerv4Scope -Name $DHCPScope -StartRange $DHCPScopeStartRange -EndRange $DHCPScopeEndRange -SubnetMask $DHCPScopeSubnetMask -LeaseDuration $DHCPScopeLeaseDuration
                }

                # Range
                if (((((Get-DhcpServerv4Scope).StartRange -ne $DHCPScopeStartRange) -or
                       (Get-DhcpServerv4Scope).EndRange -ne $DHCPScopeEndRange)) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope range $DHCPScopeStartRange-$DHCPScopeEndRange" @VerboseSplat))
                {
                    Set-DhcpServerv4Scope -ScopeID $DHCPScope -StartRange $DHCPScopeStartRange -EndRange $DHCPScopeEndRange
                }

                # SubnetMask
                if (((Get-DhcpServerv4Scope).SubnetMask -ne $DHCPScopeSubnetMask) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope subnet mask to $DHCPScopeSubnetMask" @VerboseSplat))
                {
                    Set-DhcpServerv4Scope -ScopeID $DHCPScope -SubnetMask $DHCPScopeSubnetMask
                }

                # Lease duration
                if (((Get-DhcpServerv4Scope).LeaseDuration -ne $DHCPScopeLeaseDuration) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope lease duration to $DHCPScopeLeaseDuration" @VerboseSplat))
                {
                    Set-DhcpServerv4Scope -ScopeID $DHCPScope -LeaseDuration $DHCPScopeLeaseDuration
                }

                # DNS domain
                if (-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 15 -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope DNS Domain to $env:USERDNSDOMAIN" @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeID $DHCPScope -DNSDomain $env:USERDNSDOMAIN
                }

                # DNS server
                if ((-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 6 -ErrorAction SilentlyContinue) -or
                    @(Compare-Object -ReferenceObject $DHCPScopeDNSServer -DifferenceObject (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 6).Value -SyncWindow 0).Length -ne 0) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope DNS to $DHCPScopeDNSServer" @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeID $DHCPScope -DNSServer $DHCPScopeDNSServer
                }

                # Gateway
                if (-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 3 -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope router to $DHCPScopeDefaultGateway" @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeID $DHCPScope -Router $DHCPScopeDefaultGateway
                }

                # Disable netbios
                if (-not (Get-DhcpServerv4OptionValue -ScopeId $DHCPScope -OptionId 1 -VendorClass 'Microsoft Windows 2000 Options' -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Setting DHCP scope option to disable netbios." @VerboseSplat))
                {
                    Set-DhcpServerv4OptionValue -ScopeId $DHCPScope -VendorClass 'Microsoft Windows 2000 Options' -OptionId 1 -Value 2
                }

                ###############
                # Reservations
                ###############

                $DhcpReservations =
                @(
                    @{ Name = "ADFS";  IPAddress = "$DomainNetworkId.150"; }
                    @{ Name = "AS";  IPAddress = "$DomainNetworkId.200"; }
                )

                foreach($Reservation in $DhcpReservations)
                {
                    # Set reservation name
                    $ReservationName = "$($Server.Item($Reservation.Name)).$DomainName"

                    # Get clientId from dhcp active leases
                    $ClientId = (Get-DhcpServerv4Lease -ScopeID $DHCPScope | Where-Object { $_.HostName -eq $ReservationName -and $_.AddressState -eq 'Active' } | Sort-Object -Property LeaseExpiryTime | Select-Object -Last 1).ClientId

                    # Check if client id exist
                    if ($ClientId)
                    {
                        $CurrentReservation = Get-DhcpServerv4Reservation -ScopeId $DHCPScope | Where-Object { $_.Name -eq $ReservationName -and $_.IPAddress -eq $Reservation.IPAddress }

                        if ($CurrentReservation)
                        {
                            if ($CurrentReservation.ClientId -ne $ClientId -and
                               (ShouldProcess @WhatIfSplat -Message "Updating DHCP reservation `"$($ReservationName)`" `"$($Reservation.IPAddress)`" to ($ClientID)." @VerboseSplat))
                            {
                                Set-DhcpServerv4Reservation -Name $ReservationName -IPAddress $Reservation.IPAddress -ClientId $ClientID
                            }
                        }
                        elseif (ShouldProcess @WhatIfSplat -Message "Adding DHCP reservation `"$($ReservationName)`" `"$($Reservation.IPAddress)`" for ($ClientId)." @VerboseSplat)
                        {
                            Add-DhcpServerv4Reservation -ScopeId $DHCPScope -Name $ReservationName -IPAddress $Reservation.IPAddress -ClientId $ClientID
                        }
                    }
                }
            }

            # ██████╗ ███████╗ ██████╗██╗   ██╗ ██████╗██╗     ███████╗██████╗ ██╗███╗   ██╗
            # ██╔══██╗██╔════╝██╔════╝╚██╗ ██╔╝██╔════╝██║     ██╔════╝██╔══██╗██║████╗  ██║
            # ██████╔╝█████╗  ██║      ╚████╔╝ ██║     ██║     █████╗  ██████╔╝██║██╔██╗ ██║
            # ██╔══██╗██╔══╝  ██║       ╚██╔╝  ██║     ██║     ██╔══╝  ██╔══██╗██║██║╚██╗██║
            # ██║  ██║███████╗╚██████╗   ██║   ╚██████╗███████╗███████╗██████╔╝██║██║ ╚████║
            # ╚═╝  ╚═╝╚══════╝ ╚═════╝   ╚═╝    ╚═════╝╚══════╝╚══════╝╚═════╝ ╚═╝╚═╝  ╚═══╝

            if (-not (Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" | Select-Object -ExpandProperty EnabledScopes) -and
                (ShouldProcess @WhatIfSplat -Message "Enabling Recycle Bin Feature." @VerboseSplat))
            {
                Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $DomainName -Confirm:$false > $null
            }

            #  ██████╗ ██╗   ██╗
            # ██╔═══██╗██║   ██║
            # ██║   ██║██║   ██║
            # ██║   ██║██║   ██║
            # ╚██████╔╝╚██████╔╝
            #  ╚═════╝  ╚═════╝

            $OrganizationalUnits =
            @(
                #  Name = Name of OU                            Path = Where to create OU

                @{ Name = $DomainName;                          Path = $BaseDN; }

                @{  Name = 'Computers';                         Path = "OU=$DomainName,$BaseDN"; }

                @{   Name = 'Servers';                          Path = "OU=Computers,OU=$DomainName,$BaseDN"; }

                @{    Name = 'Windows Server 2019';             Path = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"; }

                @{     Name = 'Certificate Authorities';        Path = "OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"; }
                @{     Name = 'Federation Services';            Path = "OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"; }
                @{     Name = 'Web Servers';                    Path = "OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"; }

                @{    Name = 'Windows Server';                  Path = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"; }

                @{     Name = 'Certificate Authorities';        Path = "OU=Windows Server,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"; }
                @{     Name = 'Web Application Proxy';          Path = "OU=Windows Server,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"; }

                @{   Name = 'Workstations';                     Path = "OU=Computers,OU=$DomainName,$BaseDN"; }
                @{    Name = 'Windows 10';                      Path = "OU=Workstations,OU=Computers,OU=$DomainName,$BaseDN"; }

                @{  Name = 'Groups';                            Path = "OU=$DomainName,$BaseDN"; }
                @{   Name = 'Access Control';                   Path = "OU=Groups,OU=$DomainName,$BaseDN"; }
                @{   Name = 'Certificate Authority Templates';  Path = "OU=Groups,OU=$DomainName,$BaseDN"; }
                @{   Name = 'Group Managed Service Accounts';   Path = "OU=Groups,OU=$DomainName,$BaseDN"; }
                @{   Name = 'Local Administrators';             Path = "OU=Groups,OU=$DomainName,$BaseDN"; }
                @{   Name = 'Remote Desktop Access';            Path = "OU=Groups,OU=$DomainName,$BaseDN"; }

                @{  Name = 'Users';                             Path = "OU=$DomainName,$BaseDN"; }

                @{   Name = 'Protected Users';                  Path = "OU=Users,OU=$DomainName,$BaseDN"; }
                @{   Name = 'Service Accounts';                 Path = "OU=Users,OU=$DomainName,$BaseDN"; }
            )

            foreach($Ou in $OrganizationalUnits)
            {
                # Creating domain OU
                if (-not (Get-ADOrganizationalUnit -SearchBase $Ou.Path -Filter "Name -like '$($Ou.Name)'" -ErrorAction SilentlyContinue) -and
                    (ShouldProcess @WhatIfSplat -Message "Creating OU=$($Ou.Name)" @VerboseSplat))
                {
                    New-ADOrganizationalUnit -Name $Ou.Name -Path $Ou.Path

                    switch($Ou.Name)
                    {
                        'Computers'
                        {
                            Write-Verbose -Message "Redirecting Computers to OU=$($Ou.Name),$($Ou.Path)" @VerboseSplat
                            redircmp "OU=$($Ou.Name),$($Ou.Path)" > $null
                        }
                        'Users'
                        {
                            Write-Verbose -Message "Redirecting Users to OU=$($Ou.Name),$($Ou.Path)" @VerboseSplat
                            redirusr "OU=$($Ou.Name),$($Ou.Path)" > $null
                        }
                    }
                }
            }

            #  ██████╗ ██████╗  ██████╗
            # ██╔════╝ ██╔══██╗██╔═══██╗
            # ██║  ███╗██████╔╝██║   ██║
            # ██║   ██║██╔═══╝ ██║   ██║
            # ╚██████╔╝██║     ╚██████╔╝
            #  ╚═════╝ ╚═╝      ╚═════╝

            # Directory names holding gpos
            foreach($GpoDir in @('Baseline', 'Gpo'))
            {
                # Check if gpo set exist
                if (Test-Path -Path "$env:TEMP\$GpoDir")
                {
                    # Read baseline gpos
                    foreach($GPO in (Get-ChildItem -Path "$($env:TEMP)\$GpoDir" -Directory))
                    {
                        # Get gpo name from xml
                        $GpReportXmlName = (Select-Xml -Path "$($GPO.FullName)\gpreport.xml" -XPath '/').Node.GPO.Name

                        if (-not $GpReportXmlName.StartsWith('MSFT'))
                        {
                            if (-not $GpReportXmlName.StartsWith($DomainPrefix))
                            {
                                $GpReportXmlName = "$DomainPrefix - $($GpReportXmlName.Remove(0, $GpReportXmlName.IndexOf('-') + 2))"
                            }
                        }

                        # Check if gpo exist
                        if (-not (Get-GPO -Name $GpReportXmlName -ErrorAction SilentlyContinue) -and
                            (ShouldProcess @WhatIfSplat -Message "Importing $($GPO.Name) `"$($GpReportXmlName)`"." @VerboseSplat))
                        {
                            Import-GPO -Path "$env:TEMP\$GpoDir" -BackupId $GPO.Name -TargetName $GpReportXmlName -CreateIfNeeded > $null
                        }
                    }

                    Start-Sleep -Seconds 1
                    Remove-Item -Path "$($env:TEMP)\$GpoDir" -Recurse -Force
                }
            }

            ############
            # Link GPOs
            ############

            $GPOLinks =
            @{
                $BaseDN =
                @(
                    "$DomainPrefix - Domain - Force Group Policy+"
                    "$DomainPrefix - Domain - Certificate Services Client+"
                    "$DomainPrefix - Domain - Clear Deny log on through Terminal Services+"
                    'Default Domain Policy'
                )

                "OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    "$DomainPrefix - Computer - Intranet+"
                    "$DomainPrefix - Computer - Firewall - Rules+"
                    "$DomainPrefix - Computer - Firewall - IPSec - Any - Require/Request-"
                    "$DomainPrefix - Computer - Local Groups+"
                    "$DomainPrefix - Computer - Windows Update+"
                    "$DomainPrefix - Computer - Display Settings+"
                    "$DomainPrefix - Computer - Enable SMB Encryption+"
                    "$DomainPrefix - Computer - Enable LSA Protection & Audit+"
                    "$DomainPrefix - Computer - Enable Virtualization Based Security+"
                    "$DomainPrefix - Computer - Enforce Netlogon Full Secure Channel Protection+"
                    "$DomainPrefix - Computer - Require Client LDAP Signing+"
                    "$DomainPrefix - Computer - Block Untrusted Fonts+"
                    "$DomainPrefix - Computer - Disable Telemetry+"
                    "$DomainPrefix - Computer - Disable Netbios+"
                    "$DomainPrefix - Computer - Disable LLMNR+"
                    "$DomainPrefix - Computer - Disable WPAD+"
                )

                "OU=Windows Server,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    'MSFT Windows 10 2004 and Server 2004 - Domain Security'
                    'MSFT Windows 10 2004 and Server 2004 - Defender Antivirus'
                    'MSFT Windows Server 2004 - Member Server'
                    'MSFT Internet Explorer 11 - Computer-'
                    'MSFT Internet Explorer 11 - User-'
                )

                "OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    'MSFT Windows 10 1809 and Server 2019 - Domain Security'
                    'MSFT Windows 10 1809 and Server 2019 - Defender Antivirus'
                    'MSFT Windows Server 2019 - Member Server'
                    'MSFT Internet Explorer 11 - Computer-'
                    'MSFT Internet Explorer 11 - User-'
                )

                "OU=Certificate Authorities,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    "$DomainPrefix - Computer - Auditing - Certification Services"
                )

                "OU=Federation Services,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    "$DomainPrefix - Computer - Firewall - IPSec - 80 (TCP) - Request-"
                    "$DomainPrefix - Computer - Firewall - IPSec - 443 (TCP) - Request-"
                )

                "OU=Web Application Proxy,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    "$DomainPrefix - Computer - Firewall - IPSec - 80 (TCP) - Disable Private and Public-"
                    "$DomainPrefix - Computer - Firewall - IPSec - 443 (TCP) - Disable Private and Public-"
                )

                "OU=Web Servers,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    "$DomainPrefix - Computer - Firewall - IPSec - 80 (TCP) - Request-"
                    "$DomainPrefix - Computer - Firewall - IPSec - 443 (TCP) - Request-"
                )

                "OU=Windows 10,OU=Workstations,OU=Computers,OU=$DomainName,$BaseDN" =
                @(
                    'MSFT Windows 10 2004 and Server 2004 - Domain Security'
                    'MSFT Windows 10 2004 and Server 2004 - Defender Antivirus'
                    'MSFT Windows 10 2004 - BitLocker'
                    'MSFT Windows 10 2004 - Computer'
                    'MSFT Windows 10 2004 - User'
                    'MSFT Internet Explorer 11 - Computer-'
                    'MSFT Internet Explorer 11 - User-'
                )

                "OU=Users,OU=$DomainName,$BaseDN" =
                @(
                    "$DomainPrefix - User - Display Settings"
                    "$DomainPrefix - User - Disable WPAD"
                    "$DomainPrefix - User - Disable WSH-"
                )

                "OU=Domain Controllers,$BaseDN" =
                @(
                    "$DomainPrefix - Domain Controller - Firewall - IPSec - Any - Request-"
                    "$DomainPrefix - Domain Controller - Time - PDC NTP"
                    #"$DomainPrefix - Domain Controller - Time - Non-PDC"
                    "$DomainPrefix - Computer - Firewall - Rules"
                    "$DomainPrefix - Computer - Windows Update"
                    "$DomainPrefix - Computer - Display Settings"
                    "$DomainPrefix - Computer - Enable SMB Encryption"
                    "$DomainPrefix - Computer - Enable LSA Protection & Audit"
                    "$DomainPrefix - Computer - Enable Virtualization Based Security"
                    "$DomainPrefix - Computer - Enforce Netlogon Full Secure Channel Protection"
                    "$DomainPrefix - Computer - Require Client LDAP Signing"
                    "$DomainPrefix - Computer - Block Untrusted Fonts"
                    "$DomainPrefix - Computer - Disable Telemetry"
                    "$DomainPrefix - Computer - Disable Netbios"
                    "$DomainPrefix - Computer - Disable LLMNR"
                    "$DomainPrefix - Computer - Disable WPAD"
                    'MSFT Windows Server 2019 - Domain Controller'
                    'MSFT Windows 10 1809 and Server 2019 - Domain Security'
                    'MSFT Windows 10 1809 and Server 2019 - Defender Antivirus-'
                    'MSFT Internet Explorer 11 - Computer-'
                    'MSFT Internet Explorer 11 - User-'
                    'Default Domain Controllers Policy'
                )
            }

            # Itterate targets
            foreach($Target in $GPOLinks.Keys)
            {
                $Order = 1

                # Itterate GPOs
                foreach($Gpo in ($GPOLinks.Item($Target)))
                {
                    $GPLinkSplat = @{}

                    if ($Gpo.EndsWith('+'))
                    {
                        $GPLinkSplat +=
                        @{
                            Enforced = 'Yes'
                        }

                        $Gpo = $Gpo.TrimEnd('+')
                    }
                    elseif ($Gpo.EndsWith('-'))
                    {
                        $GPLinkSplat +=
                        @{
                            LinkEnabled = 'No'
                        }

                        $Gpo = $Gpo.TrimEnd('-')
                    }

                    try
                    {
                        if (ShouldProcess @WhatIfSplat)
                        {
                            # Creating link
                            New-GPLink @GPLinkSplat -Name $Gpo -Target $Target -Order $Order -ErrorAction Stop > $null
                        }

                        Write-Verbose -Message "Created `"$Gpo`" ($Order) link under $($Target.Substring(0, $Target.IndexOf(',')))" @VerboseSplat

                        $Order++;
                    }
                    catch [Exception]
                    {
                        if ($_.Exception -match 'is already linked')
                        {
                            if (ShouldProcess @WhatIfSplat)
                            {
                                # Modifying link
                                Set-GPLink @GPLinkSplat -Name $Gpo -Target $Target -Order $Order > $null

                                $Order++;
                            }
                        }
                    }
                }
            }

            # ██╗   ██╗███████╗███████╗██████╗ ███████╗
            # ██║   ██║██╔════╝██╔════╝██╔══██╗██╔════╝
            # ██║   ██║███████╗█████╗  ██████╔╝███████╗
            # ██║   ██║╚════██║██╔══╝  ██╔══██╗╚════██║
            # ╚██████╔╝███████║███████╗██║  ██║███████║
            #  ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝

            $Users =
            @(
                @{ Name = 'Admin';            AccountNotDelegated = $true;   Password = 'P455w0rd';  MemberOf = @('Administrators', 'Domain Admins', 'Enterprise Admins', 'Group Policy Creator Owners', 'Remote Desktop Users', 'Schema Admins', 'Protected Users') }
                @{ Name = 'User';             AccountNotDelegated = $false;  Password = 'P455w0rd';  MemberOf = @() }
                @{ Name = 'Alice';            AccountNotDelegated = $false;  Password = 'P455w0rd';  MemberOf = @() }
                @{ Name = 'Bob';              AccountNotDelegated = $false;  Password = 'P455w0rd';  MemberOf = @() }
                @{ Name = 'Eve';              AccountNotDelegated = $false;  Password = 'P455w0rd';  MemberOf = @() }

                @{ Name = 'AzADDSConnector';  AccountNotDelegated = $false;  Password = 'TGF+4GLX1D6aVzTF*Wd+H?5$dajg7Eo!';  MemberOf = @() }
                #@{ Name = 'AzADDSConnector';  AccountNotDelegated = $false;  Password = 'W5iY?&oLId*@Dm2GHzu%5!b&##9!tF4Z';  MemberOf = @() }
            )

            foreach ($User in $Users)
            {
                if (-not (Get-ADUser -SearchBase "OU=Users,OU=$DomainName,$BaseDN" -SearchScope Subtree -Filter "sAMAccountName -eq '$($User.Name)'" -ErrorAction SilentlyContinue) -and
                   (ShouldProcess @WhatIfSplat -Message "Creating user `"$($User.Name)`"." @VerboseSplat))
                {
                    New-ADUser -Name $User.Name -DisplayName $User.Name -SamAccountName $User.Name -UserPrincipalName "$($User.Name)@$DomainName" -EmailAddress "$($User.Name)@$DomainName" -AccountPassword (ConvertTo-SecureString -String $User.Password -AsPlainText -Force) -ChangePasswordAtLogon $false -PasswordNeverExpires $true -Enabled $true -AccountNotDelegated $User.AccountNotDelegated

                    if ($User.MemberOf)
                    {
                        Add-ADPrincipalGroupMembership -Identity $User.Name -MemberOf $User.MemberOf
                    }
                }
            }

            # ███╗   ███╗ ██████╗ ██╗   ██╗███████╗
            # ████╗ ████║██╔═══██╗██║   ██║██╔════╝
            # ██╔████╔██║██║   ██║██║   ██║█████╗
            # ██║╚██╔╝██║██║   ██║╚██╗ ██╔╝██╔══╝
            # ██║ ╚═╝ ██║╚██████╔╝ ╚████╔╝ ███████╗
            # ╚═╝     ╚═╝ ╚═════╝   ╚═══╝  ╚══════╝

            $MoveObjects =
            @(
                @{ Filter = "Name -like 'CA*' -and ObjectClass -eq 'computer'";     TargetPath = "OU=Certificate Authorities,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" }
                @{ Filter = "Name -like 'ADFS*' -and ObjectClass -eq 'computer'";   TargetPath = "OU=Federation Services,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" }
                @{ Filter = "Name -like 'WAP*' -and ObjectClass -eq 'computer'";    TargetPath = "OU=Web Application Proxy,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" }
                @{ Filter = "Name -like 'R*' -and ObjectClass -eq 'computer'";      TargetPath = "OU=Web Application Proxy,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" }
                @{ Filter = "Name -like 'AS*' -and ObjectClass -eq 'computer'";     TargetPath = "OU=Web Servers,OU=Windows Server 2019,OU=Servers,OU=Computers,OU=$DomainName,$BaseDN" }
                @{ Filter = "Name -like 'WW*' -and ObjectClass -eq 'computer'";     TargetPath = "OU=Windows 10,OU=Workstations,OU=Computers,OU=$DomainName,$BaseDN" }

                @{ Filter = "Name -like 'Admin' -and ObjectClass -eq 'user'";       TargetPath = "OU=Protected Users,OU=Users,OU=$DomainName,$BaseDN" }
                @{ Filter = "Name -like 'Az*' -and ObjectClass -eq 'user'";         TargetPath = "OU=Service Accounts,OU=Users,OU=$DomainName,$BaseDN" }
                @{ Filter = "Name -like 'Svc*' -and ObjectClass -eq 'user'";        TargetPath = "OU=Service Accounts,OU=Users,OU=$DomainName,$BaseDN" }
            )

            foreach ($Obj in $MoveObjects)
            {
                $CurrentObj = Get-ADObject -Filter $Obj.Filter -SearchBase "OU=$DomainName,$BaseDN" -SearchScope 'Subtree'

                if ($CurrentObj -and $CurrentObj.DistinguishedName -notlike "*$($Obj.TargetPath)" -and
                   (ShouldProcess @WhatIfSplat -Message "Moving object `"$($CurrentObj.Name)`" to `"$($Obj.TargetPath)`"." @VerboseSplat))
                {
                    $CurrentObj | Move-ADObject -TargetPath $Obj.TargetPath
                }
            }

            #  ██████╗ ██████╗  ██████╗ ██╗   ██╗██████╗ ███████╗
            # ██╔════╝ ██╔══██╗██╔═══██╗██║   ██║██╔══██╗██╔════╝
            # ██║  ███╗██████╔╝██║   ██║██║   ██║██████╔╝███████╗
            # ██║   ██║██╔══██╗██║   ██║██║   ██║██╔═══╝ ╚════██║
            # ╚██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║     ███████║
            #  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝     ╚══════╝

            $DomainGroups =
            @(
                # Name        : Name & display name
                # Path        : OU location
                # SearachBase : Where to look for members
                # SearchScope : Base/OneLevel/Subtree to look for memebers
                # Filter      : Filter to get members

                @{
                    Name        = 'Domain Servers'
                    Path        = "OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -like '*' -and ObjectClass -eq 'computer'"
                }

                @{
                    Name        = 'Domain Workstations'
                    Path        = "OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Workstations,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -like '*' -and ObjectClass -eq 'computer'"
                }

                @{
                    Name        = 'Delegate Create Child Computer'
                    Path        = "OU=Access Control,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Users,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -eq 'User' -and ObjectClass -eq 'person'"
                }

                @{
                    Name        = 'Delegate AdSync Basic Read Permissions'
                    Path        = "OU=Access Control,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Users,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -eq 'AzADDSConnector' -and ObjectClass -eq 'person'"
                }

                @{
                    Name        = 'Delegate AdSync Password Hash Sync Permissions'
                    Path        = "OU=Access Control,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Users,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -eq 'AzADDSConnector' -and ObjectClass -eq 'person'"
                }

                @{
                    Name        = 'Template OCSP Response Signing'
                    Path        = "OU=Certificate Authority Templates,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "(Name -like 'CA*' -or Name -like 'AS*') -and ObjectClass -eq 'computer'"
                }

                @{
                    Name        = 'Template ADFS SSL and Service Communication'
                    Path        = "OU=Certificate Authority Templates,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -like 'ADFS*' -and ObjectClass -eq 'computer'"
                }

                @{
                    Name        = 'Template WAP SSL'
                    Path        = "OU=Certificate Authority Templates,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -like 'WAP*' -and ObjectClass -eq 'computer'"
                }
            )

            # Add computer groups
            foreach($Computer in (Get-ADObject -SearchBase "OU=Computers,OU=$DomainName,$BaseDN" -SearchScope 'Subtree' -Filter "Name -like '*' -and ObjectClass -eq 'computer'"))
            {
                $DomainGroups +=
                @{
                    Name        = "LocalAdmin-$($Computer.Name)"
                    Path        = "OU=Local Administrators,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Users,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -eq 'Admin' -and ObjectClass -eq 'person'"
                }

                $DomainGroups +=
                @{
                    Name        = "RDP-$($Computer.Name)"
                    Path        = "OU=Remote Desktop Access,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase  = "OU=Users,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter      = "Name -eq 'Admin' -and ObjectClass -eq 'person'"
                }
            }

            # Build groups
            foreach($Group in $DomainGroups)
            {
                # Check if group exist
                $ADGroup = Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -Properties member

                # Add group
                if (-not $ADGroup -and
                    (ShouldProcess @WhatIfSplat -Message "Creating `"$($Group.Name)`" group." @VerboseSplat))
                {
                    $ADGroup = New-ADGroup -Name $Group.Name -DisplayName $Group.Name -Path $Group.Path -GroupScope Global -GroupCategory Security -PassThru
                }

                # Get members
                foreach($Obj in (Get-ADObject -Filter $Group.Filter -SearchScope $Group.SearchScope -SearchBase $Group.SearchBase))
                {
                    # Add member
                    if (($ADGroup -and -not $ADGroup.Member.Where({ $_ -match $Obj.Name })) -and
                        (ShouldProcess @WhatIfSplat -Message "Adding `"$($Obj.Name)`" to `"$($ADGroup.Name)`"." @VerboseSplat))
                    {
                        Add-ADPrincipalGroupMembership -Identity $Obj -MemberOf @("$($ADGroup.Name)")
                    }
                }
            }

            # ██████╗ ███████╗██╗     ███████╗ ██████╗  █████╗ ████████╗███████╗
            # ██╔══██╗██╔════╝██║     ██╔════╝██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝
            # ██║  ██║█████╗  ██║     █████╗  ██║  ███╗███████║   ██║   █████╗
            # ██║  ██║██╔══╝  ██║     ██╔══╝  ██║   ██║██╔══██║   ██║   ██╔══╝
            # ██████╔╝███████╗███████╗███████╗╚██████╔╝██║  ██║   ██║   ███████╗
            # ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

            $AccessRight = @{}
            Get-ADObject -SearchBase "CN=Configuration,$BaseDN" -LDAPFilter "(&(objectclass=controlAccessRight)(rightsguid=*))" -Properties displayName, rightsGuid | ForEach-Object { $AccessRight.Add($_.displayName, [System.GUID] $_.rightsGuid) }

            $SchemaID = @{}
            Get-ADObject -SearchBase "CN=Schema,CN=Configuration,$BaseDN" -LDAPFilter "(schemaidguid=*)" -Properties lDAPDisplayName, schemaIDGUID | ForEach-Object { $SchemaID.Add($_.lDAPDisplayName, [System.GUID] $_.schemaIDGUID) }

            ########################
            # Create Child Computer
            ########################

            # FIX
            # remove create all child objects

            $CreateChildComputer =
            @(
                @{
                   IdentityReference        = "$DomainNetbiosName\Delegate Create Child Computer";
                   ActiveDirectoryRights    = 'CreateChild';
                   AccessControlType        = 'Allow';
                   ObjectType               = $SchemaID['computer'];
                   InheritanceType          = 'All';
                   InheritedObjectType      = '00000000-0000-0000-0000-000000000000';
                }

                @{
                   IdentityReference        = "$DomainNetbiosName\Delegate Create Child Computer";
                   ActiveDirectoryRights    = 'CreateChild';
                   AccessControlType        = 'Allow';
                   ObjectType               = '00000000-0000-0000-0000-000000000000';
                   InheritanceType          = 'Descendents';
                   InheritedObjectType      = $SchemaID['computer'];
                }
            )

            Set-Ace -DistinguishedName "OU=Computers,OU=$DomainName,$BaseDN" -AceList $CreateChildComputer

            ################################
            # AdSync Basic Read Permissions
            ################################

            $AdSyncBasicReadPermissions =
            @(
                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                    ActiveDirectoryRights = 'ReadProperty';
                    AccessControlType     = 'Allow';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritanceType       = 'Descendents';
                    InheritedObjectType   = $SchemaID['contact'];
                }

                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                    ActiveDirectoryRights = 'ReadProperty';
                    AccessControlType     = 'Allow';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritanceType       = 'Descendents';
                    InheritedObjectType   = $SchemaID['user'];
                }

                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                    ActiveDirectoryRights = 'ReadProperty';
                    AccessControlType     = 'Allow';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritanceType       = 'Descendents';
                    InheritedObjectType   = $SchemaID['group'];
                }

                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                    ActiveDirectoryRights = 'ReadProperty';
                    AccessControlType     = 'Allow';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritanceType       = 'Descendents';
                    InheritedObjectType   = $SchemaID['device'];
                }

                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                    ActiveDirectoryRights = 'ReadProperty';
                    AccessControlType     = 'Allow';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritanceType       = 'Descendents';
                    InheritedObjectType   = $SchemaID['computer'];
                }

                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                    ActiveDirectoryRights = 'ReadProperty';
                    AccessControlType     = 'Allow';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritanceType       = 'Descendents';
                    InheritedObjectType   = $SchemaID['inetOrgPerson'];
                }

                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Basic Read Permissions";
                    ActiveDirectoryRights = 'ReadProperty';
                    AccessControlType     = 'Allow';
                    ObjectType            = '00000000-0000-0000-0000-000000000000';
                    InheritanceType       = 'Descendents';
                    InheritedObjectType   = $SchemaID['foreignSecurityPrincipal'];
                }
            )

            Set-Ace -DistinguishedName $BaseDN -AceList $AdSyncBasicReadPermissions

            ########################################
            # AdSync Password Hash Sync Permissions
            ########################################

            $AdSyncPasswordHashSyncPermissions =
            @(
                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Password Hash Sync Permissions";
                    ActiveDirectoryRights = 'ExtendedRight';
                    AccessControlType     = 'Allow';
                    ObjectType            = $AccessRight['Replicating Directory Changes All'];
                    InheritanceType       = 'None';
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                }

                @{
                    IdentityReference     = "$DomainNetbiosName\Delegate AdSync Password Hash Sync Permissions";
                    ActiveDirectoryRights = 'ExtendedRight';
                    AccessControlType     = 'Allow';
                    ObjectType            = $AccessRight['Replicating Directory Changes'];
                    InheritanceType       = 'None';
                    InheritedObjectType   = '00000000-0000-0000-0000-000000000000';
                }
            )

            Set-Ace -DistinguishedName $BaseDN -AceList $AdSyncPasswordHashSyncPermissions

            #  ██████╗ ███╗   ███╗███████╗ █████╗
            # ██╔════╝ ████╗ ████║██╔════╝██╔══██╗
            # ██║  ███╗██╔████╔██║███████╗███████║
            # ██║   ██║██║╚██╔╝██║╚════██║██╔══██║
            # ╚██████╔╝██║ ╚═╝ ██║███████║██║  ██║
            #  ╚═════╝ ╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝

            ##########
            # Kds Key
            ##########

            if (-not (Get-KdsRootKey) -and
                (ShouldProcess @WhatIfSplat -Message "Adding KDS root key." @VerboseSplat))
            {
                # DC computer object must not be moved from OU=Domain Controllers
                Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) > $null
            }

            $ServiceNames =
            @(
                # Name        : Name & sAMAccountName
                # Path        : OU location
                # SearachBase : Where to look for members
                # SearchScope : Base/OneLevel/Subtree to look for memebers
                # Filter      : Filter to get members

                @{
                    Name = 'Adfs'
                    Path = "OU=Group Managed Service Accounts,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter = "Name -like 'ADFS*' -and ObjectClass -eq 'computer'"
                }

                @{
                    Name = 'PowerShell'
                    Path = "OU=Group Managed Service Accounts,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter = "Name -like '*' -and ObjectClass -eq 'computer'"
                }

                @{
                    Name = 'AzADSyncSrv'
                    Path = "OU=Group Managed Service Accounts,OU=Groups,OU=$DomainName,$BaseDN"
                    SearchBase = "OU=Servers,OU=Computers,OU=$DomainName,$BaseDN"
                    SearchScope = 'Subtree'
                    Filter = "Name -like 'AS*' -and ObjectClass -eq 'computer'"
                }
            )

            foreach ($Service in $ServiceNames)
            {
                # Check if group exist
                $Gmsa = Get-ADGroup -Filter "Name -eq 'Gmsa $($Service.Name)'" -Properties member

                # Add group
                if (-not $Gmsa -and
                    (ShouldProcess @WhatIfSplat -Message "Creating `"Gmsa$($Service.Name)`" group." @VerboseSplat))
                {
                    $Gmsa = New-ADGroup -Name "Gmsa $($Service.Name)" -sAMAccountName "Gmsa$($Service.Name)" -Path $Service.Path -GroupScope Global -GroupCategory Security -PassThru
                }

                # Get members
                foreach($Obj in (Get-ADObject -Filter $Service.Filter -SearchScope $Service.SearchScope -SearchBase $Service.SearchBase))
                {
                    # Add member
                    if (($Gmsa -and -not $Gmsa.Member.Where({ $_ -match $Obj.Name })) -and
                        (ShouldProcess @WhatIfSplat -Message "Adding `"$($Obj.Name)`" to `"$($Gmsa.Name)`"." @VerboseSplat))
                    {
                        Add-ADPrincipalGroupMembership -Identity $Obj -MemberOf @("$($Gmsa.SamAccountName)")
                    }
                }

                # Service account
                if (-not (Get-ADServiceAccount -Filter "Name -eq 'Msa$($Service.Name)'") -and
                    (ShouldProcess @WhatIfSplat -Message "Creating managed service account `"Msa$($Service.Name)`$`"." @VerboseSplat))
                {
                    New-ADServiceAccount -Name "Msa$($Service.Name)" -SamAccountName "Msa$($Service.Name)" -DNSHostName "Msa$($Service.Name).$DomainName" -PrincipalsAllowedToRetrieveManagedPassword "Gmsa$($Service.Name)"
                }
            }


            # ████████╗███████╗███╗   ███╗██████╗ ██╗      █████╗ ████████╗███████╗███████╗
            # ╚══██╔══╝██╔════╝████╗ ████║██╔══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔════╝
            #    ██║   █████╗  ██╔████╔██║██████╔╝██║     ███████║   ██║   █████╗  ███████╗
            #    ██║   ██╔══╝  ██║╚██╔╝██║██╔═══╝ ██║     ██╔══██║   ██║   ██╔══╝  ╚════██║
            #    ██║   ███████╗██║ ╚═╝ ██║██║     ███████╗██║  ██║   ██║   ███████╗███████║
            #    ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝

            # Check if templates exist
            if (Test-Path -Path "$env:TEMP\Templates")
            {
                # Set oid path
                $OidPath = "CN=OID,CN=Public Key Services,CN=Services,CN=Configuration,$BaseDN"

                # Get msPKI-Cert-Template-OID
                $msPKICertTemplateOid = Get-ADObject -Identity $OidPath -Properties msPKI-Cert-Template-OID | Select-Object -ExpandProperty msPKI-Cert-Template-OID

                # Check if msPKI-Cert-Template-OID exist
                if ($msPKICertTemplateOid)
                {
                    # Define empty acl
                    $EmptyAcl = New-Object -TypeName System.DirectoryServices.ActiveDirectorySecurity

                    # https://docs.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.objectsecurity.setaccessruleprotection?view=dotnet-plat-ext-3.1
                    $EmptyAcl.SetAccessRuleProtection($true, $false)

                    # Set template path
                    $CertificateTemplatesPath = "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$BaseDN"

                    # Read templates
                    foreach ($TemplateFile in (Get-ChildItem -Path "$env:TEMP\Templates" -Filter '*_tmpl.json'))
                    {
                        # Read template file and convert from json
                        $SourceTemplate = $TemplateFile | Get-Content | ConvertFrom-Json

                        # Add domain prefix to template name
                        $NewTemplateName = "$DomainPrefix$($SourceTemplate.Name)"

                        if (-not (Get-ADObject -SearchBase $CertificateTemplatesPath -Filter "Name -eq '$NewTemplateName' -and objectClass -eq 'pKICertificateTemplate'") -and
                            (ShouldProcess @WhatIfSplat -Message "Creating template `"$NewTemplateName`"." @VerboseSplat))
                        {
                            # https://github.com/GoateePFE/ADCSTemplate/blob/master/ADCSTemplate.psm1

                            # Generate new template oid and cn
                            do
                            {
                               $Part2 = Get-Random -Minimum 10000000 -Maximum 99999999
                               $NewOid = "$msPKICertTemplateOid.$(Get-Random -Minimum 10000000 -Maximum 99999999).$Part2"
                               $NewOidCn = "$Part2.$((1..32 | % { '{0:X}' -f (Get-Random -Max 16) }) -join '')"
                            }
                            while (

                                # Check if oid exist
                                Get-ADObject -SearchBase $OidPath -Filter "cn -eq '$NewOidCn' -and msPKI-Cert-Template-OID -eq '$NewOID'"
                            )

                            # Add domain prefix to template display name
                            $NewTemplateDisplayName = "$DomainPrefix $($SourceTemplate.DisplayName)"

                            # Oid attributes
                            $NewOidAttributes =
                            @{
                                'DisplayName' = $NewTemplateDisplayName
                                'msPKI-Cert-Template-OID' = $NewOid
                                'flags' = [System.Int32] '1'
                            }

                            # Create oid
                            New-ADObject -Path $OidPath -OtherAttributes $NewOidAttributes -Name $NewOidCn -Type 'msPKI-Enterprise-OID'

                            # Template attributes
                            $NewTemplateAttributes =
                            @{
                                'DisplayName' = $NewTemplateDisplayName
                                'msPKI-Cert-Template-OID' = $NewOid
                            }

                            # Import attributes
                            foreach ($Property in ($SourceTemplate | Get-Member -MemberType NoteProperty))
                            {
                                Switch ($Property.Name)
                                {
                                    { $_ -in @('flags',
                                               'revision',
                                               'msPKI-Certificate-Name-Flag',
                                               'msPKI-Enrollment-Flag',
                                               'msPKI-Minimal-Key-Size',
                                               'msPKI-Private-Key-Flag',
                                               'msPKI-RA-Signature',
                                               'msPKI-Template-Minor-Revision',
                                               'msPKI-Template-Schema-Version',
                                               'pKIDefaultKeySpec',
                                               'pKIMaxIssuingDepth')}
                                    {
                                        $NewTemplateAttributes.Add($_, [System.Int32]$SourceTemplate.$_)
                                        break
                                    }

                                    { $_ -in @('msPKI-Certificate-Application-Policy',
                                               'msPKI-RA-Application-Policies',
                                               'pKICriticalExtensions',
                                               'pKIDefaultCSPs',
                                               'pKIExtendedKeyUsage')}
                                    {
                                        $NewTemplateAttributes.Add($_, [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection]$SourceTemplate.$_)
                                        break
                                    }

                                    { $_ -in @('pKIExpirationPeriod',
                                               'pKIKeyUsage',
                                               'pKIOverlapPeriod')}
                                    {
                                        $NewTemplateAttributes.Add($_, [System.Byte[]]$SourceTemplate.$_)
                                        break
                                    }

                                    { $_ -in @('Name',
                                               'DisplayName')}
                                    {
                                        break
                                    }

                                    default
                                    {
                                        Write-Warning -Message "Missing handler for `"$($Property.Name)`"."
                                    }
                                }
                            }

                            # Create template
                            $NewADObj = New-ADObject -Path $CertificateTemplatesPath -Name $NewTemplateName -OtherAttributes $NewTemplateAttributes -Type 'pKICertificateTemplate' -PassThru

                            # Empty acl
                            Set-Acl -AclObject $EmptyAcl -Path "AD:$($NewADObj.DistinguishedName)"
                        }
                    }

                    # Read acl files
                    foreach ($AclFile in (Get-ChildItem -Path "$env:TEMP\Templates" -Filter '*_acl.json'))
                    {
                        # Read acl file and convert from json
                        $SourceAcl = $AclFile | Get-Content | ConvertFrom-Json

                        foreach ($Ace in $SourceAcl)
                        {
                            Set-Ace -DistinguishedName "CN=$DomainPrefix$($AclFile.BaseName.Replace('_acl', '')),$CertificateTemplatesPath" -AceList ($Ace | Select-Object -Property AccessControlType, ActiveDirectoryRights, InheritanceType, @{ n = 'IdentityReference'; e = { $_.IdentityReference.Replace('%domain%', $DomainNetbiosName) }}, ObjectType, InheritedObjectType)
                        }
                    }

                    Start-Sleep -Seconds 1
                    Remove-Item -Path "$($env:TEMP)\Templates" -Recurse -Force
                }
            }

            # ██╗      █████╗ ██████╗ ███████╗
            # ██║     ██╔══██╗██╔══██╗██╔════╝
            # ██║     ███████║██████╔╝███████╗
            # ██║     ██╔══██║██╔═══╝ ╚════██║
            # ███████╗██║  ██║██║     ███████║
            # ╚══════╝╚═╝  ╚═╝╚═╝     ╚══════╝

            if (-not (Import-Module -Name AdmPwd.PS -ErrorAction SilentlyContinue) -and
                (ShouldProcess @WhatIfSplat -Message "Installing LAPS." @VerboseSplat))
            {
                if (-not (Test-Path -Path "$env:temp\LAPS.x64.msi") -and
                    (ShouldProcess @WhatIfSplat -Message "Downloading LAPS." @VerboseSplat))
                {
                    # Download
                    try
                    {
                        (New-Object System.Net.WebClient).DownloadFile('https://download.microsoft.com/download/C/7/A/C7AAD914-A8A6-4904-88A1-29E657445D03/LAPS.x64.msi', "$env:temp\LAPS.x64.msi")
                    }
                    catch [Exception]
                    {
                        throw $_
                    }
                }

                # Start installation
                $LAPSInstallJob = Start-Job -ScriptBlock { msiexec.exe /i "$env:temp\LAPS.x64.msi" ADDLOCAL=ALL /quiet /qn /norestart }

                # Wait for installation to complete
                Wait-Job -Job $LAPSInstallJob > $null

                # Import module
                Import-Module -Name AdmPwd.PS

            }


            # FIX
            # setup logging

            # ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗      ██████╗ ██████╗  ██████╗
            # ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗    ██╔════╝ ██╔══██╗██╔═══██╗
            # ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝    ██║  ███╗██████╔╝██║   ██║
            # ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝     ██║   ██║██╔═══╝ ██║   ██║
            # ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║         ╚██████╔╝██║     ╚██████╔╝
            # ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝          ╚═════╝ ╚═╝      ╚═════╝

            if ($BackupGpo.IsPresent -and
                (ShouldProcess @WhatIfSplat -Message "Backing up GPOs to `"$env:TEMP\GpoBackup`"" @VerboseSplat))
            {
                # Remove old directory
                Remove-Item -Recurse -Path "$env:TEMP\GpoBackup" -Force -ErrorAction SilentlyContinue

                # Create new directory
                New-Item -Path "$env:TEMP\GpoBackup" -ItemType Directory > $null

                # Export
                foreach($Gpo in (Get-GPO -All | Where-Object { $_.DisplayName.StartsWith($DomainPrefix) }))
                {
                    Backup-GPO -Guid $Gpo.Id -Path "$env:TEMP\GpoBackup" > $null
                }

                foreach($file in (Get-ChildItem -Recurse -Force -Path "$env:TEMP\GpoBackup"))
                {
                    if ($file.Attributes.ToString().Contains('Hidden'))
                    {
                        Set-ItemProperty -Path $file.FullName -Name Attributes -Value Normal
                    }
                }
            }

            # ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗     ████████╗███████╗███╗   ███╗██████╗ ██╗      █████╗ ████████╗███████╗███████╗
            # ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗    ╚══██╔══╝██╔════╝████╗ ████║██╔══██╗██║     ██╔══██╗╚══██╔══╝██╔════╝██╔════╝
            # ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝       ██║   █████╗  ██╔████╔██║██████╔╝██║     ███████║   ██║   █████╗  ███████╗
            # ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝        ██║   ██╔══╝  ██║╚██╔╝██║██╔═══╝ ██║     ██╔══██║   ██║   ██╔══╝  ╚════██║
            # ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║            ██║   ███████╗██║ ╚═╝ ██║██║     ███████╗██║  ██║   ██║   ███████╗███████║
            # ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝            ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝

             if ($BackupTemplates.IsPresent -and
                (ShouldProcess @WhatIfSplat -Message "Backing up certificate templates to `"$env:TEMP\TemplatesBackup`"" @VerboseSplat))
            {
                # Remove old directory
                Remove-Item -Recurse -Path "$env:TEMP\TemplatesBackup" -Force -ErrorAction SilentlyContinue

                # Create new directory
                New-Item -Path "$env:TEMP\TemplatesBackup" -ItemType Directory > $null

                # Export
                foreach($Template in (Get-ADObject -SearchBase "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=bcl,DC=nu" -SearchScope Subtree -Filter "Name -like '$DomainPrefix*' -and objectClass -eq 'pKICertificateTemplate'" -Property *))
                {
                    # Remove domain prefix
                    $Name = $Template.Name.Replace($DomainPrefix, '')

                    # Export template to json files
                    $Template | Select-Object -Property @{ n = 'Name' ; e = { $Name }}, @{ n = 'DisplayName'; e = { $_.DisplayName.Replace("$DomainPrefix ", '') }}, flags, revision, *PKI*, @{ n = 'msPKI-Template-Minor-Revision' ; e = { 1 }} -ExcludeProperty 'msPKI-Template-Minor-Revision', 'msPKI-Cert-Template-OID' | ConvertTo-Json | Out-File -FilePath "$env:TEMP\TemplatesBackup\$($Name)_tmpl.json"

                    # Export acl to json files
                    # Note: Convert to/from csv for ToString on all enums
                    Get-Acl -Path "AD:$($Template.DistinguishedName)" | Select-Object -ExpandProperty Access | Select-Object -Property *, @{ n = 'IdentityReference'; e = { $_.IdentityReference.ToString().Replace($DomainNetbiosName, '%domain%') }} -ExcludeProperty 'IdentityReference' | ConvertTo-Csv | ConvertFrom-Csv | ConvertTo-Json | Out-File -FilePath "$env:TEMP\TemplatesBackup\$($Name)_acl.json"
                }
            }
        }
    }
}

Process
{
    # ██████╗ ██████╗  ██████╗  ██████╗███████╗███████╗███████╗
    # ██╔══██╗██╔══██╗██╔═══██╗██╔════╝██╔════╝██╔════╝██╔════╝
    # ██████╔╝██████╔╝██║   ██║██║     █████╗  ███████╗███████╗
    # ██╔═══╝ ██╔══██╗██║   ██║██║     ██╔══╝  ╚════██║╚════██║
    # ██║     ██║  ██║╚██████╔╝╚██████╗███████╗███████║███████║
    # ╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝╚══════╝╚══════╝╚══════╝

    # Remote
    if ($Session -and $Session.State -eq 'Opened')
    {
        # Load functions
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_TryCatch.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_ShouldProcess.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_GetBaseDN.ps1
        Invoke-Command -Session $Session -ErrorAction Stop -FilePath $PSScriptRoot\f_SetAce.ps1

        # Get parameters
        Invoke-Command -Session $Session -ScriptBlock `
        {
            # Splat
            $VerboseSplat = $Using:VerboseSplat
            $WhatIfSplat  = $Using:WhatIfSplat
            $ComputerName = $Using:ComputerName

            # Mandatory parameters
            $DomainName = $Using:DomainName
            $DomainNetbiosName = $Using:DomainNetbiosName
            $DomainLocalPassword = $Using:DomainLocalPassword
            $DomainNetworkId = $Using:DomainNetworkId

            # DNS
            $DNSReverseLookupZone = $Using:DNSReverseLookupZone
            $DNSRefreshInterval = $Using:DNSRefreshInterval
            $DNSNoRefreshInterval = $Using:DNSNoRefreshInterval
            $DNSScavengingInterval = $Using:DNSScavengingInterval
            $DNSScavengingState = $Using:DNSScavengingState

            # DHCP
            $DHCPScope = $Using:DHCPScope
            $DHCPScopeStartRange = $Using:DHCPScopeStartRange
            $DHCPScopeEndRange = $Using:DHCPScopeEndRange
            $DHCPScopeSubnetMask = $Using:DHCPScopeSubnetMask
            $DHCPScopeDefaultGateway = $Using:DHCPScopeDefaultGateway
            $DHCPScopeDNSServer = $Using:DHCPScopeDNSServer
            $DHCPScopeLeaseDuration = $Using:DHCPScopeLeaseDuration

            # Switches
            $BackupGpo = $Using:BackupGpo
            $BackupTemplates = $Using:BackupTemplates
        }

        # Run main
        Invoke-Command -Session $Session -ScriptBlock $MainScriptBlock
    }
    else # Locally
    {
        if ((Read-Host "Invoke locally? [y/n]") -ne 'y')
        {
            break
        }

        # Load functions
        Invoke-Command -ScriptBlock `
        {
            try
            {
                . $PSScriptRoot\f_TryCatch.ps1
                # f_ShouldProcess.ps1 loaded in Begin
                . $PSScriptRoot\f_GetBaseDN.ps1
                . $PSScriptRoot\f_SetAce.ps1
            }
            catch [Exception]
            {
                throw $_
            }

        } -NoNewScope

        # Run main
        Invoke-Command -ScriptBlock $MainScriptBlock -NoNewScope
    }
}

End
{
}

# SIG # Begin signature block
# MIIUrwYJKoZIhvcNAQcCoIIUoDCCFJwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWGKbeRjOz+0wxQZQ/w69dfo5
# ZxGggg8yMIIE9zCCAt+gAwIBAgIQJoAlxDS3d7xJEXeERSQIkTANBgkqhkiG9w0B
# AQsFADAOMQwwCgYDVQQDDANiY2wwHhcNMjAwNDI5MTAxNzQyWhcNMjIwNDI5MTAy
# NzQyWjAOMQwwCgYDVQQDDANiY2wwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQCu0nvdXjc0a+1YJecl8W1I5ev5e9658C2wjHxS0EYdYv96MSRqzR10cY88
# tZNzCynt911KhzEzbiVoGnmFO7x+JlHXMaPtlHTQtu1LJwC3o2QLAew7cy9vsOvS
# vSLVv2DyZqBsy1O7H07z3z873CAsDk6VlhfiB6bnu/QQM27K7WkGK23AHGTbPCO9
# exgfooBKPC1nGr0qPrTdHpAysJKL4CneI9P+sQBNHhx5YalmhVHr0yNeJhW92X43
# WE4IfxNPwLNRMJgLF+SNHLxNByhsszTBgebdkPA4nLRJZn8c32BQQJ5k3QTUMrnk
# 3wTDCuHRAWIp/uWStbKIgVvuMF2DixkBJkXPP1OZjegu6ceMdJ13sl6HoDDFDrwx
# 93PfUoiK7UtffyObRt2DP4TbiD89BldjxwJR1hakJyVCxvOgbelHHM+kjmBi/VgX
# Iw7UDIKmxZrnHpBrB7I147k2lGUN4Q+Uphrjq8fUOM63d9Vb9iTRJZvR7RQrPuXq
# iWlyFKcSpqOS7apgEqOnKR6tV3w/q8SPx98FuhTLi4hZak8u3oIypo4eOHMC5zqc
# 3WxxHHHUbmn/624oJ/RVJ1/JY5EZhKNd+mKtP3LTly7gQr0GgmpIGXmzzvxosiAa
# yUxlSRAV9b3RwE6BoT1wneBAF7s/QaStx1HnOvmJ6mMQrmi0aQIDAQABo1EwTzAO
# BgNVHQ8BAf8EBAMCBaAwHgYDVR0lBBcwFQYIKwYBBQUHAwMGCSsGAQQBgjdQATAd
# BgNVHQ4EFgQUEOwHbWEJldZG1P09yIHEvoP0S2gwDQYJKoZIhvcNAQELBQADggIB
# AC3CGQIHlHpmA6kAHdagusuMfyzK3lRTXRZBqMB+lggqBPrkTFmbtP1R/z6tV3Kc
# bOpRg1OZMd6WJfD8xm88acLUQHvroyDKGMSDOsCQ8Mps45bL54H+8IKK8bwfPfh4
# O+ivHwyQIfj0A44L+Q6Bmb+I0wcg+wzbtMmDKcGzq/SNqhYUEzIDo9NbVyKk9s0C
# hlV3h+N9x2SZJvZR1MmFmSf8tVCgePXMAdwPDL7Fg7np+1lZIuKu1ezG7mL8ULBn
# 81SFUn6cuOTmHm/xqZrDq1urKbauXlnUr+TwpZP9tCuihwJxLaO9mcLnKiEf+2vc
# RQYLkxk5gyUXDkP4k85qvZjc7zBFj9Ptsd2c1SMakCz3EWP8b56iIgnKhyRUVDSm
# o2bNz7MiEjp3ccwV/pMr8ub7OSqHKPSjtWW0Ccw/5egs2mfnAyO1ERWdtrycqEnJ
# CgSBtUtsXUn3rAubGJo1Q5KuonpihDyxeMl8yuvpcoYQ6v1jPG3SAPbVcS5POkHt
# DjktB0iDzFZI5v4nSl8J8wgt9uNNL3cSAoJbMhx92BfyBXTfvhB4qo862a9b1yfZ
# S4rbeyBSt3694/xt2SPhN4Sw36JD99Z68VnX7dFqaruhpyPzjGNjU/ma1n7Qdrnp
# u5VPaG2W3eV3Ay67nBLvifkIP9Y1KTF5JS+wzJoYKvZ2MIIE/jCCA+agAwIBAgIQ
# DUJK4L46iP9gQCHOFADw3TANBgkqhkiG9w0BAQsFADByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5n
# IENBMB4XDTIxMDEwMTAwMDAwMFoXDTMxMDEwNjAwMDAwMFowSDELMAkGA1UEBhMC
# VVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMSAwHgYDVQQDExdEaWdpQ2VydCBU
# aW1lc3RhbXAgMjAyMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMLm
# YYRnxYr1DQikRcpja1HXOhFCvQp1dU2UtAxQtSYQ/h3Ib5FrDJbnGlxI70Tlv5th
# zRWRYlq4/2cLnGP9NmqB+in43Stwhd4CGPN4bbx9+cdtCT2+anaH6Yq9+IRdHnbJ
# 5MZ2djpT0dHTWjaPxqPhLxs6t2HWc+xObTOKfF1FLUuxUOZBOjdWhtyTI433UCXo
# ZObd048vV7WHIOsOjizVI9r0TXhG4wODMSlKXAwxikqMiMX3MFr5FK8VX2xDSQn9
# JiNT9o1j6BqrW7EdMMKbaYK02/xWVLwfoYervnpbCiAvSwnJlaeNsvrWY4tOpXIc
# 7p96AXP4Gdb+DUmEvQECAwEAAaOCAbgwggG0MA4GA1UdDwEB/wQEAwIHgDAMBgNV
# HRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMEEGA1UdIAQ6MDgwNgYJ
# YIZIAYb9bAcBMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29t
# L0NQUzAfBgNVHSMEGDAWgBT0tuEgHf4prtLkYaWyoiWyyBc1bjAdBgNVHQ4EFgQU
# NkSGjqS6sGa+vCgtHUQ23eNqerwwcQYDVR0fBGowaDAyoDCgLoYsaHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC10cy5jcmwwMqAwoC6GLGh0dHA6
# Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtdHMuY3JsMIGFBggrBgEF
# BQcBAQR5MHcwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBP
# BggrBgEFBQcwAoZDaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# U0hBMkFzc3VyZWRJRFRpbWVzdGFtcGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOC
# AQEASBzctemaI7znGucgDo5nRv1CclF0CiNHo6uS0iXEcFm+FKDlJ4GlTRQVGQd5
# 8NEEw4bZO73+RAJmTe1ppA/2uHDPYuj1UUp4eTZ6J7fz51Kfk6ftQ55757TdQSKJ
# +4eiRgNO/PT+t2R3Y18jUmmDgvoaU+2QzI2hF3MN9PNlOXBL85zWenvaDLw9MtAb
# y/Vh/HUIAHa8gQ74wOFcz8QRcucbZEnYIpp1FUL1LTI4gdr0YKK6tFL7XOBhJCVP
# st/JKahzQ1HavWPWH1ub9y4bTxMd90oNcX6Xt/Q/hOvB46NJofrOp79Wz7pZdmGJ
# X36ntI5nePk2mOHLKNpbh6aKLzCCBTEwggQZoAMCAQICEAqhJdbWMht+QeQF2jaX
# whUwDQYJKoZIhvcNAQELBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lD
# ZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGln
# aUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTE2MDEwNzEyMDAwMFoXDTMxMDEw
# NzEyMDAwMFowcjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hB
# MiBBc3N1cmVkIElEIFRpbWVzdGFtcGluZyBDQTCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBAL3QMu5LzY9/3am6gpnFOVQoV7YjSsQOB0UzURB90Pl9TWh+
# 57ag9I2ziOSXv2MhkJi/E7xX08PhfgjWahQAOPcuHjvuzKb2Mln+X2U/4Jvr40ZH
# BhpVfgsnfsCi9aDg3iI/Dv9+lfvzo7oiPhisEeTwmQNtO4V8CdPuXciaC1TjqAlx
# a+DPIhAPdc9xck4Krd9AOly3UeGheRTGTSQjMF287DxgaqwvB8z98OpH2YhQXv1m
# blZhJymJhFHmgudGUP2UKiyn5HU+upgPhH+fMRTWrdXyZMt7HgXQhBlyF/EXBu89
# zdZN7wZC/aJTKk+FHcQdPK/P2qwQ9d2srOlW/5MCAwEAAaOCAc4wggHKMB0GA1Ud
# DgQWBBT0tuEgHf4prtLkYaWyoiWyyBc1bjAfBgNVHSMEGDAWgBRF66Kv9JLLgjEt
# UYunpyGd823IDzASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjAT
# BgNVHSUEDDAKBggrBgEFBQcDCDB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCB
# gQYDVR0fBHoweDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0QXNzdXJlZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBQBgNVHSAESTBHMDgG
# CmCGSAGG/WwAAgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQu
# Y29tL0NQUzALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggEBAHGVEulRh1Zp
# ze/d2nyqY3qzeM8GN0CE70uEv8rPAwL9xafDDiBCLK938ysfDCFaKrcFNB1qrpn4
# J6JmvwmqYN92pDqTD/iy0dh8GWLoXoIlHsS6HHssIeLWWywUNUMEaLLbdQLgcseY
# 1jxk5R9IEBhfiThhTWJGJIdjjJFSLK8pieV4H9YLFKWA1xJHcLN11ZOFk362kmf7
# U2GJqPVrlsD0WGkNfMgBsbkodbeZY4UijGHKeZR+WfyMD+NvtQEmtmyl7odRIeRY
# YJu6DC0rbaLEfrvEJStHAgh8Sa4TtuF8QkIoxhhWz0E0tmZdtnR79VYzIi8iNrJL
# okqV2PWmjlIxggTnMIIE4wIBATAiMA4xDDAKBgNVBAMMA2JjbAIQJoAlxDS3d7xJ
# EXeERSQIkTAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUv1MZYLBlM56d2/ZTjpBZy1Dwa+gwDQYJ
# KoZIhvcNAQEBBQAEggIAb8vg9bEPlRiTc4n5FxeKwjmADRm5n8E8La++uZWG1aS2
# R8C2eO/jG99ETPLfZ5UeS/dFm7eZ1kWBMvJYqTx+jhmvVojsb4lLVTS8wGjNxr/Q
# CKcfcxgv5BXUOHDIJszZJW0k0ULXJh4AXWvlk8UZzzhrU0CZmrnWNNNp9n+GuNZL
# CsZYLHxUDkSHB9O2asYZLIkrUWpzx6H7JHKRmRBwx/FJf5kNhPdRbK6jVhP8ERpG
# q38V8ioLFXBp2XDJylZ0fNLXrb+mj+XGV/6f7Y+P1avjnOCfekrrbl9ZOH4O8aEX
# S5PfbNA+FEFnrEfflshsA4vCZwrNsF5V+Z4gspaMSrnHoCysQzNbHy9gSHMZvE50
# oCyUphfvsZaJOP2o8Uiq3WINVp/bwOQ9ifUhYcl2rFRHpJLs2U5pGZM3gVgewnVN
# t6cxN9qJ+GFu+N24eX0GwZJwxlD4wEjw2bzVxc9UAtJbImoPMO6aO3Ih98+4Eq2/
# x34tfNTrc2IEoIU/0Zmi1SxTvz4iKW98F/iOAPw1f/DcGVRliIBXRkvwqUksIDq+
# ovU8fNACIeiuPgM/8FgUCQRGi+oCoByGQ0DsDTf5ZgGXwzdG0OnYA64MxeDEXhqQ
# HpzcWLl7UDTuk6MtaDRhOF7qv5zjZWumnkHIZOv3sOybO8BO2iaveUcHxzQ8N7Sh
# ggIgMIICHAYJKoZIhvcNAQkGMYICDTCCAgkCAQEwgYYwcjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIFRpbWVzdGFtcGlu
# ZyBDQQIQDUJK4L46iP9gQCHOFADw3TAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkD
# MQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjEwMTEyMTYyNzAxWjAjBgkq
# hkiG9w0BCQQxFgQUnA724qHaXYzzA7HnQ+RdzwZCU4QwDQYJKoZIhvcNAQEBBQAE
# ggEAJx5wqYPmTHQtS7Qr1J50fhKbpZ1hlzu3rVXtP4RDnq+0nrNh+ZqYZNs5DDPz
# +oS1f5vaV+YJyYmCiBAYrlS0rbMY4K9jdOP58Vq9n8aDpV4QaUw5XjTtlOwCnbS9
# 8TEHaLTIwJn9oz0XV/bd8JeElfch3JRVtzjPzcGkKT+Son3dAYiqj3M9ANSqN4dh
# ArHMENgf1LorV/C/QltAy5soBx5xpgIeT5GaOVGwFb0e1f2hWIlE09kjoTSRDVH1
# dzMS+krB63A9TzY1W7/OBrdBwMsNsRh9wQKVXw1H9TKLaHvl6BCdcfbJFlwKnQ9F
# gZht2YU4enLDADkUambSnN0Ojg==
# SIG # End signature block