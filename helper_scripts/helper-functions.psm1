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
}
# Export the function
Export-ModuleMember -Function Install-Dbatools

Function Build-SampleDatabases {
    param (
        [string]$ServerInstance = "localhost",
        [string]$DatabaseName = "Northwind",
        [string]$DataFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\SampleDB.mdf",
        [string]$LogFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\SampleDB_log.ldf"
    )

    Write-Error "Implement this function"

}

Function Build-DatabaseFromBackup {
    param (
        [string]$ServerInstance = "localhost",
        [string]$DatabaseName = "Northwind",
        [string]$BackupFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup\SampleDB.bak"
    )

    Write-Error "Implement this function"
}