# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$EnableSSIS,  # it is not possible to pass a bool through the Invoke-RemoteScript interface
    [Parameter(Mandatory = $true, HelpMessage = "Server lockdown command")]
    [string]$ServerLockdownCommandB64,
    [Parameter(Mandatory = $true, HelpMessage = "Domain-qualified name for the SQL admin group")]
    [string]$SqlAdminGroup,
    [Parameter(Mandatory = $true, HelpMessage = "Password for SQL AuthUpdate User")]
    [string]$SqlAuthUpdateUserPassword,
    [Parameter(Mandatory = $true, HelpMessage = "Name of SQL AuthUpdate User")]
    [string]$SqlAuthUpdateUsername,
    [Parameter(Mandatory = $true, HelpMessage = "Domain-qualified name for the SRE research users group")]
    [string]$SreResearchUsersGroup
)

Import-Module SqlServer

$serverName = $(hostname)
$secureSqlAuthUpdateUserPassword = (ConvertTo-SecureString $SqlAuthUpdateUserPassword -AsPlainText -Force)
$sqlAdminCredentials = New-Object System.Management.Automation.PSCredential($SqlAuthUpdateUsername, $secureSqlAuthUpdateUserPassword)
$connectionTimeoutInSeconds = 5
$EnableSSIS = [System.Convert]::ToBoolean($EnableSSIS)


# Ensure that SSIS is enabled/disabled as requested
# -------------------------------------------------
if ($EnableSSIS) {
    Write-Output "Ensuring that SSIS services (SSISTELEMETRY150, MsDtsServer150) are enabled on: '$serverName'"
    Get-Service SSISTELEMETRY150, MsDtsServer150 | Start-Service -PassThru | Set-Service -StartupType Automatic
} else {
    Write-Output "Ensuring that SSIS services (SSISTELEMETRY150, MsDtsServer150) are disabled on: '$serverName'"
    Get-Service SSISTELEMETRY150, MsDtsServer150 | Stop-Service -PassThru | Set-Service -StartupType Disabled
}
if ($?) {
    Write-Output " [o] Successfully updated SSIS services state on: '$serverName'"
} else {
    Write-Output " [x] Failed to updated SSIS services state on: '$serverName'!"
    exit 1
}


# Disable unused SQL Server services
# ----------------------------------
Write-Output "Disable unused SQL server services on: '$serverName'..."
Get-Service SSASTELEMETRY, MSSQLServerOlapService, SQLBrowser | Stop-Service -PassThru | Set-Service -StartupType disabled
if ($?) {
    Write-Output " [o] Successfully disabled unused services (SSASTELEMETRY, MSSQLServerOlapService, SQLBrowser) on: '$serverName'"
} else {
    Write-Output " [x] Failed to disable unused SQL server services on: '$serverName'!"
    exit 1
}


# Check whether the auth update user exists and has admin rights
# --------------------------------------------------------------
Write-Output "Checking that the $SqlAuthUpdateUsername user has admin permissions on: '$serverName'..."
$loginExists = Get-SqlLogin -ServerInstance $serverName -Credential $sqlAdminCredentials -ErrorAction SilentlyContinue -ErrorVariable operationFailed | Where-Object { $_.Name -eq $SqlAuthUpdateUsername }
$smo = (New-Object Microsoft.SqlServer.Management.Smo.Server $serverName)
$smo.ConnectionContext.LoginSecure = $false  # disable the default use of Windows credentials
$smo.ConnectionContext.set_Login($sqlAdminCredentials.UserName)
$smo.ConnectionContext.set_SecurePassword($sqlAdminCredentials.Password)
$isAdmin = $smo.Roles | Where-Object { $_.Name -Like "*admin*" } | Where-Object { $_.EnumServerRoleMembers() -Contains $SqlAuthUpdateUsername }

# If the SqlAuthUpdateUsername is not found then something has gone wrong
if ($operationFailed -Or (-Not $loginExists)) {
    Write-Output " [x] $SqlAuthUpdateUsername does not exist on: '$serverName'!"
    exit 1

# If the SqlAuthUpdateUsername is not an admin, then we are not able to do anything else.
# Hopefully this is because lockdown has already been run.
} elseif (-Not $isAdmin) {
    Write-Output " [o] $SqlAuthUpdateUsername is not an admin on: '$serverName'. Have you already locked this server down?"

# ... otherwise we continue with the server lockdown
} else {
    Write-Output " [o] $SqlAuthUpdateUsername has admin privileges on: '$serverName'"

    # Give the configured domain groups login access to the SQL Server
    # ----------------------------------------------------------------
    foreach ($domainGroup in @($SqlAdminGroup, $SreResearchUsersGroup)) {
        Write-Output "Ensuring that '$domainGroup' domain group has SQL login access to: '$serverName'..."
        if (Get-SqlLogin -ServerInstance $serverName -Credential $sqlAdminCredentials | Where-Object { $_.Name -eq $domainGroup } ) {
            Write-Output " [o] '$domainGroup' already has SQL login access to: '$serverName'"
        } else {
            $_ = Add-SqlLogin -ConnectionTimeout $connectionTimeoutInSeconds -GrantConnectSql -ServerInstance $serverName -LoginName $domainGroup -LoginType "WindowsGroup" -Credential $sqlAdminCredentials -ErrorAction SilentlyContinue -ErrorVariable operationFailed
            if ($? -And -Not $operationFailed) {
                Write-Output " [o] Successfully gave '$domainGroup' SQL login access to: '$serverName'"
            } else {
                Write-Output " [x] Failed to give '$domainGroup' SQL login access to: '$serverName'!"
                exit 1
            }
        }
    }


    # Give domain groups appropriate roles on the SQL Server
    # ------------------------------------------------------
    foreach($groupRoleTuple in @(($SqlAdminGroup, "sysadmin"), ($SreResearchUsersGroup, "db_datareader"))) {
        $domainGroup, $role = $groupRoleTuple
        Write-Output "Giving '$domainGroup' the $role role on: '$serverName'..."
        # For admin roles we need 'sp_addsrvrolemember' but for other roles we need 'sp_addrolemember'
        # These two commands use the opposite ordering for group and role for some reason
        # NB. Powershell versions lower than 7 have no ternary operator so we need this awkward syntax
        $sqlCommand = $(
            if ($role -Like "*admin*") {
                "exec sp_addsrvrolemember '$domainGroup', '$role'"
            } else {
                "exec sp_addrolemember '$role', '$domainGroup'"
            }
        )
        Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $sqlCommand -ErrorAction SilentlyContinue -ErrorVariable operationFailed
        if ($? -And -Not $operationFailed) {
            Write-Output " [o] Successfully gave '$domainGroup' the $role role on: '$serverName'"
            Start-Sleep -s 10  # allow time for the database action to complete
        } else {
            Write-Output " [x] Failed to give '$domainGroup' the $role role on: '$serverName'!"
            Write-Output "Failed SQL command was: $sqlCommand"
            exit 1
        }
    }


    # Run the scripted SQL Server lockdown
    # ------------------------------------
    Write-Output "Running T-SQL lockdown script on: '$serverName'..."
    $ServerLockdownCommand = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($ServerLockdownCommandB64))
    Invoke-SqlCmd -ServerInstance $serverName -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $ServerLockdownCommand -ErrorAction SilentlyContinue -ErrorVariable operationFailed
    if ($? -And -Not $operationFailed) {
        Write-Output " [o] Successfully ran T-SQL lockdown script on: '$serverName'"
    } else {
        Write-Output " [x] Failed to run T-SQL lockdown script on: '$serverName'!"
        exit 1
    }


    # Revoke the sysadmin role from the SQL AuthUpdateUser used when building the SQL Server
    # --------------------------------------------------------------------------------------
    Write-Output "Revoking sysadmin role from $SqlAuthUpdateUsername on: '$serverName'..."
    $dropAdminCommand = "ALTER SERVER ROLE sysadmin DROP MEMBER $SqlAuthUpdateUsername"
    Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $dropAdminCommand -ErrorAction SilentlyContinue -ErrorVariable operationFailed
    if ($? -And -Not $operationFailed) {
        Write-Output " [o] Successfully revoked sysadmin role on: '$serverName'"
    } else {
        Write-Output " [x] Failed to revoke sysadmin role on: '$serverName'!"
        exit 1
    }
}
