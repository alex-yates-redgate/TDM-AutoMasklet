Function Install-Dbatools {
    param (
        $autoContinue = $false,
        $trustCert = $true
    )
    # Installing and importing dbatools
    if (Get-InstalledModule | Where-Object {$_.Name -like "dbatools"}){
        # dbatools already installed
        Write-Verbose "  dbatools PowerShell Module is installed."
        return $true
    }
    else {
        # dbatools not installed yet
        Write-Verbose "  dbatools PowerShell Module is not installed"
        Write-Verbose "    Installing dbatools (requires admin privileges)."

        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $runningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $runningAsAdmin){
            Write-Error "    Script not running as admin. Please either install dbatools manually, or run this script as an administrator to enable installing PowerShell modules."
            return $false
        }
        if ($autoContinue) {
            install-module dbatools -Confirm:$False -Force
        }
        else {
            install-module dbatools
        }
        
    }
    Write-Verbose "  Importing dbatools PowerShell module."
    import-module dbatools

    if ($trustCert){
        Write-Warning "Note: For convenience, trustCert is set to true. This is not best practice. For more information about a more secure way to manage encryption/certificates, see this post by Chrissy LeMaire: https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/"
    }
    if ($trustCert){
        # Updating the dbatools configuration for this session only to trust server certificates and not encrypt connections
        #   Note: This is not best practice. For more information about a more secure way to manage encyption/certificates, see this post by Chrissy LeMaire:
        #   https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/
        Write-Verbose "    Updating dbatools configuration (for this session only) to trust server certificates, and not to encrypt connections."
        Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true
        Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false
    }
    return $true
}
# Export the function
Export-ModuleMember -Function Install-Dbatools

Function New-SampleDatabases {
    param (
        [Parameter(Mandatory = $true)][boolean]$WinAuth,
        [Parameter(Mandatory = $true)][string]$sqlInstance,
        [Parameter(Mandatory = $true)][string]$sourceDb,
        [Parameter(Mandatory = $true)][string]$targetDb,
        [Parameter(Mandatory = $true)][string]$fullRestoreCreateScript,
        [Parameter(Mandatory = $true)][string]$subsetCreateScript,
        [PSCredential]$SqlCredential
    )

    # If exists, drop the source and target databases
    Write-Verbose "  If exists, dropping the source and target databases"
    if ($winAuth){
        $dbsToDelete = Get-DbaDatabase -SqlInstance $sqlInstance -Database $sourceDb,$targetDb
    }
    else {
        $dbsToDelete = Get-DbaDatabase -SqlInstance $sqlInstance -Database $sourceDb,$targetDb -SqlCredential $SqlCredential
    }

    forEach ($db in $dbsToDelete.Name){
        Write-Verbose "    Dropping database $db"
        $sql = "ALTER DATABASE $db SET single_user WITH ROLLBACK IMMEDIATE; DROP DATABASE $db;"
        Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql -SqlCredential $SqlCredential
    }

    # Create the fullRestore and subset databases
    Write-Verbose "  Creating the fullRestore and subset databases"
    New-DbaDatabase -SqlInstance $sqlInstance -Name $sourceDb, $targetDb -SqlCredential $SqlCredential | Out-Null
    
    Write-Verbose "    Creating the $sourceDb database objects and data"
    Invoke-DbaQuery -SqlInstance $sqlInstance -Database $sourceDb -File $fullRestoreCreateScript -SqlCredential $SqlCredential | Out-Null
    
    Write-Verbose "    Creating the $targetDb database objects"
    Invoke-DbaQuery -SqlInstance $sqlInstance -Database $targetDb -File $subsetCreateScript -SqlCredential $SqlCredential | Out-Null
    
    Write-Verbose "  Validating that the databases have been created correctly"
    $totalFullRestoreOrders = (Invoke-DbaQuery -SqlInstance $sqlInstance -Database $sourceDb -Query "SELECT COUNT (*) AS TotalOrders FROM dbo.Orders" -SqlCredential $SqlCredential).TotalOrders
    $totalSubsetOrders = (Invoke-DbaQuery -SqlInstance $sqlInstance -Database $targetDb -Query "SELECT COUNT (*) AS TotalOrders FROM dbo.Orders" -SqlCredential $SqlCredential).TotalOrders    
    
    if ($totalFullRestoreOrders -ne 830){
        Write-Error "    There should be 830 rows in $sourceDb, but there are $totalFullRestoreOrders."
        return $false
    }
    if ($totalSubsetOrders -ne 0){
        Write-Error "    There should be 0 rows in $targetDb, but there are $totalSubsetOrders."
        return $false
    }
    return $true
}
# Export the function
Export-ModuleMember -Function New-SampleDatabases

Function Restore-StagingDatabasesFromBackup {
    param (
        [Parameter(Mandatory = $true)][boolean]$WinAuth,
        [Parameter(Mandatory = $true)][string]$sqlInstance,
        [Parameter(Mandatory = $true)][string]$sourceDb,
        [Parameter(Mandatory = $true)][string]$targetDb,
        [Parameter(Mandatory = $true)][string]$sourceBackupPath,
        [PSCredential]$SqlCredential
    )
    Restore-DbaDatabase -SqlInstance $sqlInstance -Path $sourceBackupPath -WithReplace -DatabaseName $sourceDb -DestinationFileSuffix "_FULLRESTORE" -ReplaceDbNameInFile -Confirm:$false -SqlCredential $SqlCredential | Out-Null
    Set-DbaDbRecoveryModel -SqlInstance $sqlInstance -RecoveryModel Simple -Database $sourceDb -Confirm:$false -SqlCredential $SqlCredential | Out-Null
    Restore-DbaDatabase -SqlInstance $sqlInstance -Path $sourceBackupPath -WithReplace -DatabaseName $targetDb -DestinationFileSuffix "_SUBSET" -ReplaceDbNameInFile -Confirm:$false -SqlCredential $SqlCredential | Out-Null
    Set-DbaDbRecoveryModel -SqlInstance $sqlInstance -RecoveryModel Simple -Database $targetDb -Confirm:$false -SqlCredential $SqlCredential | Out-Null
    
    $sourceDbRecoveryModel = (Test-DbaDbRecoveryModel -SqlInstance $sqlInstance -Database $sourceDb -SqlCredential $SqlCredential ).ActualRecoveryModel
    $targetDbRecoveryModel = (Test-DbaDbRecoveryModel -SqlInstance $sqlInstance -Database $targetDb -SqlCredential $SqlCredential ).ActualRecoveryModel

    return $true
}
# Export the function
Export-ModuleMember -Function Restore-StagingDatabasesFromBackup