param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Get SRE virtual network
# -----------------------
Add-LogMessage -Level Info "Removing all existing mirror peerings..."
$sreVnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.Name -ResourceGroupName $config.sre.network.vnet.rg


# Remove SHM side of mirror peerings involving this SRE
# -----------------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$mirrorVnets = Get-AzVirtualNetwork | Where-Object { $_.Name -like "*MIRROR*" }
foreach ($mirrorVnet in $mirrorVnets) {
    $mirrorPeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName
    foreach ($mirrorPeering in $mirrorPeerings) {
        # Remove peerings that involve this SRE
        if ($mirrorPeering.RemoteVirtualNetwork.Id -eq $sreVnet.Id) {
            Add-LogMessage -Level Info "[ ] Removing peering $($mirrorPeering.Name): $($mirrorPeering.VirtualNetworkName) -> $($sreVnet.Name)"
            $_ = Remove-AzVirtualNetworkPeering -Name $mirrorPeering.Name -VirtualNetworkName $mirrorVnet.Name -ResourceGroupName $mirrorVnet.ResourceGroupName -Force
            if ($?) {
                Add-LogMessage -Level Success "Peering removal succeeded"
            } else {
                Add-LogMessage -Level Fatal "Peering removal failed!"
            }
        }
    }
}


# Remove peering to this SRE from each SHM mirror network
# -------------------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$srePeerings = Get-AzVirtualNetworkPeering -Name "*" -VirtualNetwork $sreVnet.Name -ResourceGroupName $sreVnet.ResourceGroupName
foreach ($srePeering in $srePeerings) {
    # Remove peerings that involve any of the mirror VNets
    $peeredVnets = $mirrorVnets | Where-Object { $_.Id -eq $srePeering.RemoteVirtualNetwork.Id }
    foreach ($mirrorVnet in $peeredVnets) {
        Add-LogMessage -Level Info "[ ] Removing peering $($srePeering.Name): $($srePeering.VirtualNetworkName) -> $($mirrorVnet.Name)"
        $_ = Remove-AzVirtualNetworkPeering -Name $srePeering.Name -VirtualNetworkName $sreVnet.Name -ResourceGroupName $sreVnet.ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Peering removal succeeded"
        } else {
            Add-LogMessage -Level Fatal "Peering removal failed!"
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext