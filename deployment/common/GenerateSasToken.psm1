# Generate a new SAS token
# ------------------------
function New-AccountSasToken {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter subscription name")]
        [string]$subscriptionName,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Enter storage account resource group")]
        [string]$resourceGroup,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Enter storage account name")]
        [string]$accountName,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Enter service(s) - one or more of Blob,File,Table,Queue")]
        $service,
        [Parameter(Position = 4, Mandatory = $true, HelpMessage = "Enter resource type(s) - one or more of Service,Container,Object")]
        $resourceType,
        [Parameter(Position = 5, Mandatory = $true, HelpMessage = "Enter permission string")]
        [string]$permission,
        [Parameter(Position = 6, Mandatory = $false, HelpMessage = "Enter validity in hours")]
        [int]$validityHours = 2
    )

    # Temporarily switch to storage account subscription
    $originalContext = Get-AzContext
    $_ = Set-AzContext -Subscription $subscriptionName

    # Generate SAS token
    $accountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -AccountName $accountName).Value[0];
    $accountContext = (New-AzStorageContext -StorageAccountName $accountName -StorageAccountKey $accountKey);
    $expiryTime = ((Get-Date) + (New-TimeSpan -Hours $validityHours))
    $sasToken = (New-AzStorageAccountSASToken -Service $service -ResourceType $resourceType -Permission $permission -ExpiryTime $expiryTime -Context $accountContext);

    # Switch back to previous subscription
    $_ = Set-AzContext -Context $originalContext;
    return $sasToken
}
Export-ModuleMember -Function New-AccountSasToken


# Generate a new read-only SAS token
# ----------------------------------
function New-ReadOnlyAccountSasToken {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter subscription name")]
        [string]$subscriptionName,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Enter storage account resource group")]
        [string]$resourceGroup,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Enter storage account name")]
        [string]$accountName
    )
    return New-AccountSasToken -subscriptionName "$subscriptionName" `
                               -resourceGroup "$resourceGroup" `
                               -AccountName "$accountName" `
                               -Service Blob,File `
                               -ResourceType Service,Container,Object `
                               -Permission "rl"
}
Export-ModuleMember -Function New-ReadOnlyAccountSasToken