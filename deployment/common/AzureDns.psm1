Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop

# Add A (and optionally CNAME) DNS records
# ----------------------------------------
function Deploy-DNSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS subscription")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to add the records to")]
        [string]$ZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Public IP address for this record to point to")]
        [string]$PublicIpAddress,
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'A' record")]
        [string]$RecordNameA = "@",
        [Parameter(Mandatory = $false, HelpMessage = "Name of certificate provider for CAA record")]
        [string]$RecordNameCAA = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Name of 'CNAME' record (if none is provided then no CNAME redirect will be set up)")]
        [string]$RecordNameCName = $null,
        [Parameter(Mandatory = $false, HelpMessage = "TTL seconds for the DNS records")]
        [int]$TtlSeconds = 30
    )
    $originalContext = Get-AzContext
    try {
        Add-LogMessage -Level Info "Adding DNS records..."
        $null = Set-AzContext -Subscription $SubscriptionName -ErrorAction Stop

        # Set the A record
        Add-LogMessage -Level Info "[ ] Setting 'A' record to '$PublicIpAddress' for DNS zone ($ZoneName)"
        Remove-AzDnsRecordSet -Name $RecordNameA -RecordType A -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName
        $null = New-AzDnsRecordSet -Name $RecordNameA -RecordType A -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName -Ttl $TtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $PublicIpAddress)
        if ($?) {
            Add-LogMessage -Level Success "Successfully set 'A' record"
        } else {
            Add-LogMessage -Level Fatal "Failed to set 'A' record!"
        }
        # Set the CNAME record
        if ($RecordNameCName) {
            Add-LogMessage -Level Info "[ ] Setting CNAME record '$RecordNameCName' to point to the 'A' record for DNS zone ($ZoneName)"
            Remove-AzDnsRecordSet -Name $RecordNameCName -RecordType CNAME -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName
            $null = New-AzDnsRecordSet -Name $RecordNameCName -RecordType CNAME -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName -Ttl $TtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $ZoneName)
            if ($?) {
                Add-LogMessage -Level Success "Successfully set 'CNAME' record"
            } else {
                Add-LogMessage -Level Fatal "Failed to set 'CNAME' record!"
            }
        }
        # Set the CAA record
        if ($RecordNameCAA) {
            Add-LogMessage -Level Info "[ ] Setting CAA record for $ZoneName to state that certificates will be provided by $RecordNameCAA"
            Remove-AzDnsRecordSet -Name "@" -RecordType CAA -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName
            $null = New-AzDnsRecordSet -Name "@" -RecordType CAA -ZoneName $ZoneName -ResourceGroupName $ResourceGroupName -Ttl $TtlSeconds -DnsRecords (New-AzDnsRecordConfig -CaaFlags 0 -CaaTag "issue" -CaaValue $RecordNameCAA)
            if ($?) {
                Add-LogMessage -Level Success "Successfully set 'CAA' record for $ZoneName"
            } else {
                Add-LogMessage -Level Fatal "Failed to set 'CAA' record for $ZoneName!"
            }
        }
    } catch {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        throw
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
    return
}
Export-ModuleMember -Function Deploy-DNSRecords


# Get NS Records
# --------------
function Get-NSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of record set")]
        [string]$RecordSetName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Reading NS records '$($RecordSetName)' for DNS Zone '$($DnsZoneName)'..."
    $recordSet = Get-AzDnsRecordSet -ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Name $RecordSetName -RecordType "NS"
    return $recordSet.Records
}
Export-ModuleMember -Function Get-NSRecords


# Create DNS Zone if it does not exist
# ------------------------------------
function New-DNSZone {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Ensuring that DNS zone '$($Name)' exists..."
    $null = Get-AzDnsZone -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating DNS Zone '$Name'"
        $null = New-AzDnsZone -Name $Name -ResourceGroupName $ResourceGroupName
        if ($?) {
            Add-LogMessage -Level Success "Created DNS Zone '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create DNS Zone '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "DNS Zone '$Name' already exists"
    }
}
Export-ModuleMember -Function New-DNSZone


# Add NS Record Set to DNS Zone if it does not already exist
# ---------------------------------------------------------
function Set-DnsZoneAndParentNSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to create")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group holding DNS zones")]
        [string]$ResourceGroupName
    )
    # Get subdomain and parent domain
    $subdomain = $DnsZoneName.Split('.')[0]
    $parentDnsZoneName = $DnsZoneName -replace "$subdomain.", ""

    # Create DNS Zone
    New-DNSZone -Name $DnsZoneName -ResourceGroupName $ResourceGroupName

    # Get NS records from the new DNS Zone
    Add-LogMessage -Level Info "Get NS records from the new DNS Zone..."
    $nsRecords = Get-NSRecords -RecordSetName "@" -DnsZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName

    # Check if parent DNS Zone exists in same subscription and resource group
    $null = Get-AzDnsZone -Name $parentDnsZoneName -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "No existing DNS Zone was found for '$parentDnsZoneName' in resource group '$ResourceGroupName'."
        Add-LogMessage -Level Info "You need to add the following NS records to the parent DNS system for '$parentDnsZoneName': '$nsRecords'"
    } else {
        # Add NS records to the parent DNS Zone
        Add-LogMessage -Level Info "Add NS records to the parent DNS Zone..."
        Set-NSRecords -RecordSetName $subdomain -DnsZoneName $parentDnsZoneName -ResourceGroupName $ResourceGroupName -NsRecords $nsRecords
    }
}
Export-ModuleMember -Function Set-DnsZoneAndParentNSRecords


# Add NS Record Set to DNS Zone if it doesn't already exist
# ---------------------------------------------------------
function Set-NSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of record set")]
        [string]$RecordSetName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "NS records to add")]
        $NsRecords
    )
    $null = Get-AzDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $DnsZoneName -Name $RecordSetName -RecordType NS -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "Creating new Record Set '$($RecordSetName)' in DNS Zone '$($DnsZoneName)' with NS records '$($nsRecords)' to ..."
        $null = New-AzDnsRecordSet -Name $RecordSetName -ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Ttl 3600 -RecordType NS -DnsRecords $NsRecords
        if ($?) {
            Add-LogMessage -Level Success "Created DNS Record Set '$RecordSetName'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create DNS Record Set '$RecordSetName'!"
        }
    } else {
        # It's not straightforward to modify existing record sets idempotently so if the set already exists we do nothing
        Add-LogMessage -Level InfoSuccess "DNS record set '$RecordSetName' already exists. Will not update!"
    }
}
Export-ModuleMember -Function Set-NSRecords
