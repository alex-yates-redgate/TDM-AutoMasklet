param (
    $sqlInstance = "localhost",
    $sqlUser = "",
    $sqlPassword = "",
    $output = "C:/temp/auto-masklet",
    $trustCert = $true,
    [switch]$autoContinue,
    [switch]$skipAuth
)

# Configuration
$databaseName = "Northwind"
$sourceDb = "${databaseName}_FullRestore"
$targetDb = "${databaseName}_Subset"
$fullRestoreCreateScript = "$PSScriptRoot/helper_scripts/CreateNorthwindFullRestore.sql"
$subsetCreateScript = "$PSScriptRoot/helper_scripts/CreateNorthwindSubset.sql"
$installTdmClisScript = "$PSScriptRoot/helper_scripts/installTdmClis.ps1"
$PromptContinue = "$PSScriptRoot/helper_scripts/PromptContinue.ps1"

$winAuth = $true
$sourceConnectionString = ""
$targetConnectionString = ""
if (($sqlUser -like "") -and ($sqlPassword -like "")){    
    $sourceConnectionString = "`"server=$sqlInstance;database=$sourceDb;Trusted_Connection=yes;TrustServerCertificate=yes`""
    $targetConnectionString = "`"server=$sqlInstance;database=$targetDb;Trusted_Connection=yes;TrustServerCertificate=yes`""
}
else {
    $winAuth = $false
    $SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sqlUser, (ConvertTo-SecureString $sqlPassword -AsPlainText -Force)
    $sourceConnectionString = "server=$sqlInstance;database=$sourceDb;TrustServerCertificate=yes;User Id=$sqlUser;Password=$sqlPassword;"
    $targetConnectionString = "server=$sqlInstance;database=$targetDb;TrustServerCertificate=yes;User Id=$sqlUser;Password=$sqlPassword;"
}

Write-Output "Configuration:"
Write-Output "- sqlInstance:             $sqlInstance"
Write-Output "- databaseName:            $databaseName"
Write-Output "- sourceDb:                $sourceDb"
Write-Output "- targetDb:                $targetDb"  
Write-Output "- fullRestoreCreateScript: $fullRestoreCreateScript"
Write-Output "- subsetCreateScript:      $subsetCreateScript"
Write-Output "- installTdmClisScript:    $installTdmClisScript"
Write-Output "- Using Windows Auth:      $winAuth"
Write-Output "- sourceConnectionString:  $sourceConnectionString"
Write-Output "- targetConnectionString:  $targetConnectionString"
Write-Output "- output:                  $output"
Write-Output "- trustCert:               $trustCert"
Write-Output ""
Write-Output "Initial setup:"

# Unblocking all files in thi repo (typically required if code is downloaded as zip)
Get-ChildItem -Path $PSScriptRoot -Recurse | Unblock-File

# Installing and importing dbatools
if (Get-InstalledModule | Where-Object {$_.Name -like "dbatools"}){
    # dbatools already installed
    Write-Output "  dbatools PowerShell Module is installed."
}
else {
    # dbatools not installed yet
    Write-Output "  dbatools PowerShell Module is not installed"
    Write-Output "    Installing dbatools (requires admin privileges)."

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $runningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $runningAsAdmin){
        Write-Warning "    Script not running as admin. Please either install dbatools manually, or run this script as an administrator to enable installing PowerShell modules."
        break
    }
    if ($autoContinue) {
        install-module dbatools -Confirm:$False -Force
    }
    else {
        install-module dbatools
    }
    
}
Write-Output "  Importing dbatools PowerShell module."

import-module dbatools

if ($trustCert){
    Write-Warning "Note: For convenience, trustCert is set to true. This is not best practice. For more information about a more secure way to manage encryption/certificates, see this post by Chrissy LeMaire: https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/"
}
if ($trustCert){
    # Updating the dbatools configuration for this session only to trust server certificates and not encrypt connections
    #   Note: This is not best practice. For more information about a more secure way to manage encyption/certificates, see this post by Chrissy LeMaire:
    #   https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/
    Write-Output "    Updating dbatools configuration (for this session only) to trust server certificates, and not to encrypt connections."
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true
    Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false
}

# Download/update rgsubset and rganonymize CLIs
Write-Output "  Ensuring the following Redgate Test Data Manager CLIs are installed and up to date: rgsubset, rganonymize"
powershell -File  $installTdmClisScript 

# Refreshing the environment variables so that the new path is available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Verifying that the CLIs are both available
$rganonymizeExe = (Get-Command rganonymize).Source
$rgsubsetExe = (Get-Command rgsubset).Source
if (-not $rganonymizeExe){
    Write-Warning "Warning: Failed to install rganonymize."
}
if (-not $rgsubsetExe) {
    Write-Warning "Warning: Failed to install rgsubset."
}

if (-not ($rganonymizeExe -and $rgsubsetExe)){
    Write-Error "Error: rgsubset and/or rganonymize CLIs not found. This script should have installed them. Please review any errors/warnings above."
    break
}

# Start trial
if (-not $skipAuth){
    Write-Output "  Authorizing rgsubset, and starting a trial (if not already started):"
    Write-Output "    rgsubset auth login --i-agree-to-the-eula --start-trial"
    rgsubset auth login --i-agree-to-the-eula --start-trial
    Write-Output "  Authorizing rganonymize:"
    Write-Output "    rganonymize auth login --i-agree-to-the-eula"
    rganonymize auth login --i-agree-to-the-eula
}

# Logging the CLI versions for reference
Write-Output ""
Write-Output "rgsubset version is:"
rgsubset --version
Write-Output "rganonymize version is:"
rganonymize --version
Write-Output ""

# If exists, drop the source and target databases
Write-Output "  If exists, dropping the source and target databases"
if ($winAuth){
    $dbsToDelete = Get-DbaDatabase -SqlInstance $sqlInstance -Database $sourceDb,$targetDb
}
else {
    $dbsToDelete = Get-DbaDatabase -SqlInstance $sqlInstance -Database $sourceDb,$targetDb -SqlCredential $SqlCredential
}

forEach ($db in $dbsToDelete.Name){
    Write-Output "    Dropping database $db"
    $sql = "ALTER DATABASE $db SET single_user WITH ROLLBACK IMMEDIATE; DROP DATABASE $db;"
    if ($winAuth){
        Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql
    }
    else {
        Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql -SqlCredential $SqlCredential
    }
}

# Create the fullRestore and subset databases
Write-Output "  Creating the fullRestore and subset databases"
if ($winAuth){
    New-DbaDatabase -SqlInstance $sqlInstance -Name $sourceDb, $targetDb | Out-Null
}
else {
    New-DbaDatabase -SqlInstance $sqlInstance -Name $sourceDb, $targetDb -SqlCredential $SqlCredential | Out-Null
}
Write-Output "    Creating the $sourceDb database objects and data"
if ($winAuth){
    Invoke-DbaQuery -SqlInstance $sqlInstance -Database $sourceDb -File $fullRestoreCreateScript | Out-Null
}
else {
    Invoke-DbaQuery -SqlInstance $sqlInstance -Database $sourceDb -File $fullRestoreCreateScript -SqlCredential $SqlCredential | Out-Null
}
Write-Output "    Creating the $targetDb database objects"
if ($winAuth){
    Invoke-DbaQuery -SqlInstance $sqlInstance -Database $targetDb -File $subsetCreateScript | Out-Null
}
else {
    Invoke-DbaQuery -SqlInstance $sqlInstance -Database $targetDb -File $subsetCreateScript -SqlCredential $SqlCredential | Out-Null
}

# Clean output directory
Write-Output "  Cleaning the output directory at: $output"
if (Test-Path $output){
    Write-Output "    Recursively deleting the existing output directory, and any files from previous runs."
    Remove-Item -Recurse -Force $output | Out-Null
}
Write-Output "    Creating a clean output directory."
New-Item -ItemType Directory -Path $output | Out-Null

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "There should now be two databases on the $sqlInstance server: $sourceDb and $targetDb"
Write-Output "$sourceDb should contain some data"
Write-Output "$targetDb should have an identical schema, but no data"
Write-Output ""
Write-Output "For example, you could run the following script in your prefered IDE:"
Write-Output ""
Write-Output "  USE $sourceDb"
Write-Output "  --USE $targetDb -- Uncomment to run the same query on the target database"
Write-Output "  "
Write-Output "  SELECT COUNT (*) AS TotalOrders"
Write-Output "  FROM   dbo.Orders;"
Write-Output "  "
Write-Output "  SELECT   TOP 20 o.OrderID AS 'o.OrderId' ,"
Write-Output "                  o.CustomerID AS 'o.CustomerID' ,"
Write-Output "                  o.ShipAddress AS 'o.ShipAddress' ,"
Write-Output "                  o.ShipCity AS 'o.ShipCity' ,"
Write-Output "                  c.Address AS 'c.Address' ,"
Write-Output "                  c.City AS 'c.ShipCity'"
Write-Output "  FROM     dbo.Customers c"
Write-Output "           JOIN dbo.Orders o ON o.CustomerID = c.CustomerID"
Write-Output "  ORDER BY o.OrderID ASC;"
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the following rgsubset command to copy a subset of the data from $sourceDb to $targetDb."
Write-Output "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --options-file `".\helper_scripts\rgsubset-options.json`" --target-database-write-mode Overwrite"
Write-Output "The subset will include data from the $startingTable table, based on the filter clause $filterClause."
Write-Output "It will also include any data from any other tables that are required to maintain referential integrity."
Write-Output "*********************************************************************************************************"
Write-Output ""

& $PromptContinue 


# running subset
Write-Output ""
Write-Output "Running rgsubset to copy a subset of the data from $sourceDb to $targetDb."
rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --options-file ".\helper_scripts\rgsubset-options.json" --target-database-write-mode Overwrite

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "$targetDb should contain some data."
Write-Output "Observe that the $startingTable table contains only data that meets the filter clause $filterClause."
Write-Output "Observe that other tables contain data required to maintain referential integrity."
Write-Output "You can see how much data has been included from for each table by reviewing the rgsubset output (above)."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run rganonymize classify to create a classification.json file, documenting the location of any PII:"
Write-Output "  rganonymize classify --database-engine SqlServer --connection-string $targetConnectionString --classification-file `"$output\classification.json`" --output-all-columns"
Write-Output "*********************************************************************************************************"
Write-Output ""

& $PromptContinue

Write-Output "Creating a classification.json file in $output"
rganonymize classify --database-engine SqlServer --connection-string=$targetConnectionString --classification-file "$output\classification.json" --output-all-columns 

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "Review the classification.json file save at: $output"
Write-Output "This file documents any PII that has been found automatically in the $targetDb database."
Write-Output "You can tweak this file as necessary and keep it in source control to inform future masking runs."
Write-Output "You could even create CI builds that cross reference this file against your database source code,"
Write-Output "  to ensure developers always add appropriate classifications for new columns before they get"
Write-Output "  deployed to production."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the rganonymize map command to create a masking.json file, defining how the PII will be masked:"
Write-Output "  rganonymize map --classification-file `"$output\classification.json`" --masking-file `"$output\masking.json`""
Write-Output "*********************************************************************************************************"
Write-Output ""

& $PromptContinue

Write-Output "Creating a masking.json file based on contents of classification.json in $output"
rganonymize map --classification-file="$output\classification.json" --masking-file="$output\masking.json" 

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "Review the masking.json file save at: $output"
Write-Output "This file defines how the PII found in the $targetDb database will be masked."
Write-Output "You can save this in source control, and set up an automated masking job to"
Write-Output "  create a fresh masked copy, with the latest data, on a nightly or weekly"
Write-Output "  basis, or at an appropriate point in your sprint/release cycle."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the rganonymize mask command to mask the PII in ${targetDb}:"
Write-Output "  rganonymize mask --database-engine SqlServer --connection-string $targetConnectionString --masking-file `"$output\masking.json`""
Write-Output "*********************************************************************************************************"
Write-Output ""

& $PromptContinue

Write-Output "Masking target database, based on contents of masking.json file in $output"
rganonymize mask --database-engine SqlServer --connection-string=$targetConnectionString --masking-file="$output\masking.json" 

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "The data in the $targetDb database should now be masked."
Write-Output "Review the data in the _FullRestore and _Subset databases. Are you happy with the way they have been subsetted and masked?"
Write-Output "Things you may like to look out for:"
Write-Output "  - Notes fields (e.g. Employees.Notes)"
Write-Output "  - Dependencies (e.g. Orders.ShipAddress and Customers.Address, joined on the CustoemrID column in each table"
Write-Output "  - Empty tables (e.g. the flyway_schema_history table)"
Write-Output ""
Write-Output "Additional tasks:"
Write-Output "To ensure that all the data you want/need gets included in the subset, review this documentation about using config files"
Write-Output "  specify multiple starting tables with additional filter clauses, e.g. 'WHERE 1=1': "
Write-Output "  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/subsetting/subsetting-configuration/subsetting-configuration-file"
Write-Output "To apply a more thorough mask on the notes fields, review this documentation, and configure this project to a Lorem Ipsum"
Write-Output "  masking rule for any 'notes' fields:"
Write-Output "  - Default classifications and datasets:"
Write-Output "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/default-classifications-and-datasets"
Write-Output "  - Applying custom classification rules:"
Write-Output "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/custom-configuration/classification-rules"
Write-Output "  - Using different or custom data sets:"
Write-Output "    https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization/custom-configuration/using-different-or-custom-datasets"
Write-Output ""
Write-Output "Once you have verified that all the PII has been removed, you can backup this version of"
Write-output "  the database, and share it with your developers for dev/test purposes."
Write-Output ""
Write-Output "**************************************   FINISHED!   **************************************"
Write-Output ""
Write-Output "CONGRATULATIONS!"
Write-Output "You've completed a minimal viable Test Data Manager proof of concept."
Write-Output "Next, review the following resources:"
Write-Output "  - Documentation:  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli"
Write-Output "  - Training:       https://www.red-gate.com/hub/university/courses/test-data-management/cloning/overview/introduction-to-tdm"
Write-Output "Can you subset and mask one of your own databases?"
Write-Output ""
Write-Output "Want to learn more? If you have a Redgate account manager, they can help you get started."
Write-Output "Otherwise, email us, and let's start a conversation: sales@red-gate.com"
