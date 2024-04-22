param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. 'project')")]
    [string]$shmId
)

Import-Module Az.Monitor -ErrorAction Stop
Import-Module Az.Maintenance -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create resource group if it does not exist
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.monitoring.rg -Location $config.location


# Deploy log analytics workspace
# ------------------------------
$workspace = Deploy-LogAnalyticsWorkspace -Name $config.monitoring.loggingWorkspace.name -ResourceGroupName $config.monitoring.rg -Location $config.location


# Connect log analytics workspace to private link scope
# Note that we cannot connect a private endpoint directly to a log analytics workspace
# ------------------------------------------------------------------------------------
$logAnalyticsLink = Deploy-MonitorPrivateLinkScope -Name $config.monitoring.privatelink.name -ResourceGroupName $config.monitoring.rg
$null = Connect-PrivateLinkToLogWorkspace -LogAnalyticsWorkspace $workspace -PrivateLinkScope $logAnalyticsLink


# Create private endpoint for the log analytics link
# --------------------------------------------------------------------------
$monitoringSubnet = Get-Subnet -Name $config.network.vnet.subnets.monitoring.name -VirtualNetworkName $config.network.vnet.name -ResourceGroupName $config.network.vnet.rg
$logAnalyticsEndpoint = Deploy-MonitorPrivateLinkScopeEndpoint -PrivateLinkScope $logAnalyticsLink -Subnet $monitoringSubnet -Location $config.location


# Create private DNS records for each endpoint DNS entry
# ------------------------------------------------------
$DnsConfigs = $accountEndpoint.CustomDnsConfigs + $logAnalyticsEndpoint.CustomDnsConfigs
# Only these exact domains are available as privatelink.{domain} through Azure Private DNS
# See https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns
$PrivateLinkDomains = @(
    "agentsvc.azure-automation.net",
    "azure-automation.net", # note this must come after 'agentsvc.azure-automation.net'
    "blob.core.windows.net",
    "monitor.azure.com",
    "ods.opinsights.azure.com",
    "oms.opinsights.azure.com"
)
foreach ($DnsConfig in $DnsConfigs) {
    $BaseDomain = $PrivateLinkDomains | Where-Object { $DnsConfig.Fqdn.Endswith($_) } | Select-Object -First 1 # we want the first (most specific) match
    if ($BaseDomain) {
        $privateZone = Deploy-PrivateDnsZone -Name "privatelink.${BaseDomain}" -ResourceGroup $config.network.vnet.rg
        $recordName = $DnsConfig.Fqdn.Substring(0, $DnsConfig.Fqdn.IndexOf($BaseDomain) - 1)
        $null = Deploy-PrivateDnsRecordSet -Name $recordName -ZoneName $privateZone.Name -ResourceGroupName $privateZone.ResourceGroupName -PrivateIpAddresses $DnsConfig.IpAddresses -Ttl 10
        # Connect the private DNS zones to all virtual networks in the SHM
        # Note that this must be done before connecting the VMs to log analytics to ensure that they use the private link
        foreach ($virtualNetwork in Get-VirtualNetwork -ResourceGroupName $config.network.vnet.rg) {
            $null = Connect-PrivateDnsToVirtualNetwork -DnsZone $privateZone -VirtualNetwork $virtualNetwork
        }
    }
    else {
        Add-LogMessage -Level Fatal "No zone created for '$($DnsConfig.Fqdn)'!"
    }
}


# Create Data Collection Rule
# ---------------------------

New-AzDataCollectionRule -RuleName $config.monitoring.dataCollection.ruleName -ResourceGroupName $config.monitoring.rg -JsonFilePath $PSScriptRoot/../arm_templates/shm-monitoring-dcr-template.json
$dcr = Get-AzDataCollectionRule -ResourceGroupName $config.monitoring.rg -Name $config.monitoring.dataCollection.ruleName


# Create Data Collection Endpoint
# -------------------------------
New-AzDataCollectionEndpoint -ResourceGroupName $config.monitoring.rg -DataCollectionRuleId $dcr.id -Name $config.monitoring.dataCollection.endpointName


# Create Maintenance Configuration
# -------------------------------
New-AzMaintenanceConfiguration  -ResourceGroupName $config.monitoring.rg `
                                -Name testingmaint `
                                -Location $config.location `
                                -MaintenanceScope "InGuestPatch" `
                                -StartDateTime "2024-04-09 01:00" `
                                -Duration 03:55 `
                                -TimeZone "GMT Standard Time" `
                                -RecurEvery "7Day" `
                                -ExtensionProperty @{inGuestPatchMode = "User" } `
                                -LinuxParameterClassificationToInclude @('Critical', 'Security') `
                                -WindowParameterClassificationToInclude @('Critical', 'Security') `
                                -InstallPatchRebootSetting "IfRequired"