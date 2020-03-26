# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
    [parameter(HelpMessage="Enter FQDN of management domain i.e. turingsafehaven.ac.uk")]
    [ValidateNotNullOrEmpty()]
    [String]$sreFqdn,
    [parameter(HelpMessage="Enter username of an admin")]
    [ValidateNotNullOrEmpty()]
    [String]$sreDcAdminUsername,
    [parameter(HelpMessage="Enter encrypted password of an admin")]
    [ValidateNotNullOrEmpty()]
    [String]$sreDcAdminPasswordEncrypted
)

# Access local domain
Write-Host "Accessing local domain..."
$localShmDomainConnection = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
if ($?) {
    Write-Host " [o] Accessing local (SHM) domain succeeded"
} else {
    Write-Host " [x] Accessing local (SHM) domain failed!"
    throw "Failed to access local domain!"
}

# Checking whether that trust relationship exists
Write-Host " [ ] Ensuring that trust relationship exists..."
$relationshipExists = $false
foreach($relationship in $localShmDomainConnection.GetAllTrustRelationships()) {
    if (($relationship.TargetName -eq $sreFqdn) -and ($relationship.TrustDirection -eq "Bidirectional")){
      $relationshipExists = $true
    }
}

# Create relationship if it does not exist
if ($relationshipExists) {
    Write-Host " [o] Bidirectional trust relationship already exists"
} else {
    Write-Host " [ ] Creating new trust relationship..."

    # Convert encrypted string to secure string and then to plaintext
    $sreDcAdminPasswordSecureString = ConvertTo-SecureString -String $sreDcAdminPasswordEncrypted -Key (1..16)
    $sreDcAdminPassword = [System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($sreDcAdminPasswordSecureString))

    # Keep retrying access until a cap is reached
    $retryElapsedSec = 0
    $maxRetrySec = 200
    $retryIntervalSec = 10
    $success = $false

    # Attempt to access remote domain. Failure here can indicate a DNS problem.
    # In particular if the conditional forwarders on the SHM DC and/or the SRE DC
    # have been configured incorrectly then attempting to resolve the FQDN into
    # an IP address will fail
    Write-Host " [ ] Accessing remote domain '$sreFqdn'..."
    while ($success -eq $false ) {
        $remoteSreDirectoryContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext("Domain", $sreFqdn, $sreDcAdminUsername, $sreDcAdminPassword)
        $remoteSreDomainConnection = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($remoteSreDirectoryContext)
        if ($?) {
            $success = $true
            Write-Host " [o] Accessing remote (SRE) domain succeeded"
        } else {
            $retryElapsedSec += $retryIntervalSec
            if ($retryElapsedSec -gt $maxRetrySec) {
                Write-Host " [x] Accessing remote (SRE) domain failed after '$retryElapsedSec' seconds!"
                throw "Failed to access remote domain!"
            } else {
                Write-Host " [ ] Accessing remote (SRE) domain failed after '$retryElapsedSec' seconds - sleeping and retrying"
                Start-Sleep -Seconds $retryIntervalSec
            }
        }
    }

    # Create trust relationship
    $localShmDomainConnection.CreateTrustRelationship($remoteSreDomainConnection, "Bidirectional")
    if ($?) {
        Write-Host " [o] Creating new trust relationship succeeded"
    } else {
        Write-Host " [x] Creating new trust relationship failed!"
        throw "Failed to create trust relationship!"
    }
}


