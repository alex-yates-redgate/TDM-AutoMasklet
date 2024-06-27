# config
$sqlInstance = "localhost"
$databaseName = "Northwind"
$sourceDb = "${databaseName}_FullRestore"
$targetDb = "${databaseName}_Subset"
$gitRoot = & git rev-parse --show-toplevel
$backupPath = "$gitRoot\backups\Northwind.bak"
$startingTable = "dbo.Orders"
$filterClause = """OrderId < 10260"""
$sourceConnectionString = """server=${serverinstance};database=${sourceDb};Integrated Security=yes;TrustServerCertificate=yes"""
$targetConnectionString = """server=${serverinstance};database=${targetDb};Integrated Security=yes;TrustServerCertificate=yes"""
$output = "C:/temp/auto-masklet"
$trustCert = $true

Write-Output "Configuration:"
Write-Output "- sqlInstance: $sqlInstance"
Write-Output "- databaseName: $databaseName"
Write-Output "- sourceDb: $sourceDb"
Write-Output "- targetDb: $targetDb"  
Write-Output "- gitRoot: $gitRoot"    
Write-Output "- backupPath: $backupPath"
Write-Output "- startingTable: $startingTable"
Write-Output "- filterClause: $filterClause"
Write-Output "- sourceConnectionString: $sourceConnectionString"
Write-Output "- targetConnectionString: $targetConnectionString"
Write-Output "- output: $output"
Write-Output "- trustCert: $trustCert"
if ($trustCert){
    Write-Warning "Note: For convenience, trustCert is set to true. This is not best practice. For more information about a more secure way to manage encryption/certificates, see this post by Chrissy LeMaire: https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/"
}

# Installing and importing dbatools
Write-Output ""
if (Get-InstalledModule | Where-Object {$_.Name -like "dbadrgtools"}){
    # dbatools not installed yet
    Write-Output "dbatools not installed yet: Installing and importing module."
    install-module dbatools
    import-module dbatools
}
else {
    # dbatools already installed
    Write-Output "dbatools already installed: Importing module."
    import-module dbatools
}

if ($trustCert){
    # Updating the dbatools configuration for this session only to trust server certificates and not encrypt connections
    #   Note: This is not best practice. For more information about a more secure way to manage encyption/certificates, see this post by Chrissy LeMaire:
    #   https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/
    Write-Output "Updating dbatools configuration (for this session only) to trust server certificates, and not to encrypt connections."
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true
    Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false
}

# Download/update subsetter and anonymize CLIs
Write-Output ""
Write-Output "Installing and configuring the following Redgate Test Data Manager CLIs: subsetter, anonymize"
Write-Warning "Downloading subsetter and anonymize CLIs not yet implemented. Please do this manually."

# If exists, drop the source and target databases
Write-Output ""
Write-Output "If exists, dropping the source and target databases"
$dbsToDelete = Get-DbaDatabase -SqlInstance localhost -Database $sourceDb,$targetDb
forEach ($db in $dbsToDelete.Name){
    Write-Output "  Dropping database $db"
    $sql = "ALTER DATABASE $db SET single_user WITH ROLLBACK IMMEDIATE; DROP DATABASE $db;"
    Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql
}

# Clean output directory
Write-Output ""
Write-Output "Cleaning the output directory at: $output"
if (Test-Path $output){
    Write-Output "  Recursively deleting the existing output directory, and any files from previous runs."
    Remove-Item -Recurse -Force $output
}
Write-Output "  Creating a clean output directory."
New-Item -ItemType Directory -Path $output

# Restore the Northwind database
Write-Output ""
Write-Output "Restoring the Northwind database, with name $sourceDb, from the backup file $backupPath"
Restore-DbaDatabase -SqlInstance $sqlInstance -Path $backupPath -DatabaseName $sourceDb -ReplaceDbNameInFile -WithReplace -DestinationFileSuffix "_FullRestore"

# Create a schema only copy
Write-Output ""
Write-Output "Creating a schema-only copy of the Northwind database, with name $targetDb"
$sql = "DBCC CLONEDATABASE ( $sourceDb , $targetDb ); ALTER DATABASE $targetDb SET READ_WRITE WITH ROLLBACK IMMEDIATE;"
Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql | Write-Output

Write-Output ""
Write-Output "Observe:"
Write-Output "There should now be two databases on the $sqlInstance server: $sourceDb and $targetDb"
Write-Output "$sourceDb should contain some data"
Write-Output "$targetDb should have an identical schema, but no data"
Write-Output ""
Write-Output "Next:"
Write-Output "We will run subsetter to copy a subset of the data from $sourceDb to $targetDb."
Write-Output "The subset will include data from the $startingTable table, based on the filter clause $filterClause."
Write-Output "It will also include any data from any other tables that are required to maintain referential integrity."
Write-Output ""
$continue = Read-Host "Continue? (y/n)"
if ($continue -notlike "y"){
    Write-output 'Response not like "y". Teminating script.'
    break
}

# running subset
Write-Output ""
Write-Output "Running subsetter"
subsetter --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --starting-table=$startingTable --filter-clause=$filterClause

Write-Output ""
Write-Output "Observe:"
Write-Output "$targetDb should contain some data."
Write-Output "Observe that the $startingTable table contains only data that meets the filter clause $filterClause."
Write-Output "Observe that other tables, contain data required to maintain referential integrity."
Write-Output "You can see how much data has been included from for each table by reviewing the subsetter output (above)."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run anonymize classify to create a classification.json file, documenting the location of any PII:"
Write-Output "  anonymize classify --database-engine SqlServer --connection-string $targetConnectionString --classification-file $output\classification.json --output-all-columns"

Write-Output ""
$continue = Read-Host "Continue? (y/n)"
if ($continue -notlike "y"){
    Write-output 'Response not like "y". Teminating script.'
    break
}

Write-Warning "Creating a classification.json file in $output"
anonymize classify --database-engine SqlServer --connection-string $targetConnectionString --classification-file "$output\classification.json" --output-all-columns

Write-Output ""
Write-Output "Observe:"
Write-Output "Review the classification.json file save at: $output"
Write-Output "This file documents any PII that has been found automatically in the $targetDb database."
Write-Output "You can tweak this file as necessary and keep it in source control to inform future masking runs."
Write-Output "You could even create CI builds that cross reference this file against your database source code,"
Write-Output "  to ensure developers always add appropriate classifications for new columns before they get"
Write-Output "  deployed to production."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the anonymize map command to create a masking.json file, defining how the PII will be masked:"
Write-Output "  anonymize map --classification-file $output\classification.json --masking-file $output\masking.json"

Write-Output ""
$continue = Read-Host "Continue? (y/n)"
if ($continue -notlike "y"){
    Write-output 'Response not like "y". Teminating script.'
    break
}

anonymize map --classification-file "$output\classification.json" --masking-file "$output\masking.json"

Write-Output ""
Write-Output "Observe:"
Write-Output "Review the masking.json file save at: $output"
Write-Output "This file defines how the PII found in the $targetDb database will be masked."
Write-Output "You can save this in source control, and set up an automated masking job to"
Write-Output "  create a fresh masked copy, with the latest data, on a nightly or weekly"
Write-Output "  basis, or at an appropriate point in your sprint/release cycle."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the anonymize mask command to mask the PII in ${targetDb}:"
Write-Output "  anonymize map --classification-file $output\classification.json --masking-file $output\masking.json"

Write-Output ""
$continue = Read-Host "Continue? (y/n)"
if ($continue -notlike "y"){
    Write-output 'Response not like "y". Teminating script.'
    break
}

anonymize mask --database-engine SqlServer --connection-string $targetConnectionString --masking-file "$output\masking.json"
Write-Output ""
Write-Output "Observe:"
Write-Output "The data in the $targetDb database should now be masked."
Write-Output "Once you have verified that all the PII has been removed,"
Write-Output "  you can backup this version of the database, and share"
Write-Output "  it with your developers for dev/test purposes."
Write-Output ""
Write-Output "Congratulations, you've completed a minimal viable Test Data Manager proof of concept!"
Write-Output "Next, review the following resources:"
Write-Output "  Documentation: "
Write-Output "  Training: "
Write-Output "Can you subset and mask one of your own databases?"
Write-Output ""
Write-Output "Want to learn more? If you have a Redgate account manager, they can help you get started."
Write-Output "Otherwise, email us and let's start a conversation: sales@red-gate.com"