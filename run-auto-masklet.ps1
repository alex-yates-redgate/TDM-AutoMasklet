param (
    $sqlInstance = "localhost",
    $sqlUser = "",
    $sqlPassword = "",
    $output = "C:/temp/auto-masklet",
    $trustCert = $true,
    $backupPath = "",
    $databaseName = "Northwind",
    [switch]$autoContinue,
    [switch]$skipAuth,
    [switch]$noRestore,
    [switch]$iAgreeToTheRedgateEula
)

# Userts must agree to the Redgate Eula, either by using the -iAgreeToTheRedgateEula parameter, or by responding to a prompt
if (-not $iAgreeToTheRedgateEula){
    if ($autoContinue){
        Write-Error 'If using the -autoContinue parameter, the -iAgreeToTheRedgateEula parameter is also required.'
        break
    }
    else {
        $eulaResponse = Read-Host "Do you agree to the Redgate End User License Agreement (EULA)? (y/n)"
        if ($eulaResponse -notlike "y"){
            Write-output 'Response not like "y". Teminating script.'
            break
        }
    }
}

# Configuration
$sourceDb = "${databaseName}_FullRestore"
$targetDb = "${databaseName}_Subset"
$fullRestoreCreateScript = "$PSScriptRoot/helper_scripts/CreateNorthwindFullRestore.sql"
$subsetCreateScript = "$PSScriptRoot/helper_scripts/CreateNorthwindSubset.sql"
$installTdmClisScript = "$PSScriptRoot/helper_scripts/installTdmClis.ps1"
$helperFunctions = "$PSScriptRoot/helper_scripts/helper-functions.psm1"
$subsetterOptionsFile = "$PSScriptRoot\helper_scripts\rgsubset-options-northwind.json"

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
Write-Output "- helperFunctions:         $helperFunctions"
Write-Output "- subsetterOptionsFile:    $subsetterOptionsFile"
Write-Output "- Using Windows Auth:      $winAuth"
Write-Output "- sourceConnectionString:  $sourceConnectionString"
Write-Output "- targetConnectionString:  $targetConnectionString"
Write-Output "- output:                  $output"
Write-Output "- trustCert:               $trustCert"
Write-Output "- backupPath:              $backupPath"
Write-Output "- noRestore:               $noRestore"
Write-Output ""
Write-Output "Initial setup:"

# Unblocking all files in thi repo (typically required if code is downloaded as zip)
Get-ChildItem -Path $PSScriptRoot -Recurse | Unblock-File

# Importing helper functions
Write-Output "  Importing helper functions"
import-module $helperFunctions
$requiredFunctions = @(
    "Install-Dbatools",
    "New-SampleDatabases",
    "Restore-StagingDatabasesFromBackup"
)
# Testing that all the required functions are available
$requiredFunctions | ForEach-Object {
    if (-not (Get-Command $_ -ErrorAction SilentlyContinue)){
        Write-Error "  Error: Required function $_ not found. Please review any errors above."
        exit
    }
    else {
        Write-Output "    $_ found."
    }
}

# Installing/importing dbatools
Write-Output "  Installing dbatools"
$dbatoolsInstalledSuccessfully = Install-Dbatools -autoContinue:$autoContinue -trustCert:$trustCert
if ($dbatoolsInstalledSuccessfully){
    Write-Output "    dbatools installed successfully"
}
else {
    Write-Error "    dbatools failed to install. Please review any errors above."
    break
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

# Skipping restore, user has created databases
if ($noRestore){
    Write-Output "*********************************************************************************************************"
    Write-Output "Skipping database restore and creation."
    Write-Output "Please ensure that the source and target databases are already created and available on the $sqlInstance server."
    Write-Output "*********************************************************************************************************"
}
else {
    # Building staging databases
  if ($backupPath) {
    # Using the Restore-StagingDatabasesFromBackup function in helper-functions.psm1 to build source and target databases from an existing backup
    Write-Output "  Building $sourceDb and $targetDb databases from backup file saved at $BackupPath."
    $dbCreateSuccessful = Restore-StagingDatabasesFromBackup -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -sourceBackupPath:$backupPath -SqlCredential:$SqlCredential
    if ($dbCreateSuccessful){
        Write-Output "    Source and target databases created successfully."
    }
    else {
        Write-Error "    Error: Failed to create the source and target databases. Please review any errors above."
        break
    }
  }
  else {
    # Using the Build-SampleDatabases function in helper-functions.psm1, and provided sql create scripts, to build sample source and target databases
    Write-Output "  Building sample Northwind source and target databases."
    $dbCreateSuccessful = New-SampleDatabases -WinAuth:$winAuth -sqlInstance:$sqlInstance -sourceDb:$sourceDb -targetDb:$targetDb -fullRestoreCreateScript:$fullRestoreCreateScript -subsetCreateScript:$subsetCreateScript -SqlCredential:$SqlCredential
    if ($dbCreateSuccessful){
        Write-Output "    Source and target databases created successfully."
    }
    else {
        Write-Error "    Error: Failed to create the source and target databases. Please review any errors above."
        break
    }
  }
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
if ($backupPath){
    Write-Output "$targetDb should be identical. In an ideal world, it would be schema identical, but empty of data."
}
else {
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
}
Write-Output ""
Write-Output "Next:"
Write-Output "We will run the following rgsubset command to copy a subset of the data from $sourceDb to $targetDb."
if ($backupPath){
    Write-Output "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --target-database-write-mode Overwrite"
}
else {
    Write-Output "  rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --options-file `"$subsetterOptionsFile`" --target-database-write-mode Overwrite"
    Write-Output "The subset will include data from the starting table, based on the options set here: $subsetterOptionsFile."
}
Write-Output "*********************************************************************************************************"
Write-Output ""

# Creating the function for Y/N prompt

function Prompt-Continue {

    if ($autoContinue) {
        Write-Output 'Auto-continue mode enabled. Proceeding without user input.'
    } else {
        $continueLoop = $true

        while ($continueLoop) {
            $continue = Read-Host "Continue? (y/n)"
            switch ($continue.ToLower()) {
                "y" { Write-Output 'User chose to continue.'; $continueLoop = $false }
                "n" { Write-Output 'User chose "n". Terminating script.'; exit }
                default { Write-Output 'Invalid response. Please enter "y" or "n".' }
            }
        }
    }
}


Prompt-Continue

# running subset
Write-Output ""
Write-Output "Running rgsubset to copy a subset of the data from $sourceDb to $targetDb."
if ($backupPath){
    rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --target-database-write-mode Overwrite
}
else {
    rgsubset run --database-engine=sqlserver --source-connection-string=$sourceConnectionString --target-connection-string=$targetConnectionString --options-file="$subsetterOptionsFile" --target-database-write-mode Overwrite
}


Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "$targetDb should contain a subset of the data from $sourceDb."
Write-Output ""
Write-Output "Next:"
Write-Output "We will run rganonymize classify to create a classification.json file, documenting the location of any PII:"
Write-Output "  rganonymize classify --database-engine SqlServer --connection-string $targetConnectionString --classification-file `"$output\classification.json`" --output-all-columns"
Write-Output "*********************************************************************************************************"
Write-Output ""

Prompt-Continue

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

Prompt-Continue

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

Prompt-Continue

Write-Output "Masking target database, based on contents of masking.json file in $output"
rganonymize mask --database-engine SqlServer --connection-string=$targetConnectionString --masking-file="$output\masking.json"

Write-Output ""
Write-Output "*********************************************************************************************************"
Write-Output "Observe:"
Write-Output "The data in the $targetDb database should now be masked."
Write-Output "Review the data in the $sourceDb and $targetDb databases. Are you happy with the way they have been subsetted and masked?"
Write-Output "Things you may like to look out for:"
Write-Output "  - Notes fields (e.g. Employees.Notes)"
Write-Output "  - Dependencies (e.g. If using the sample Northwind database, observer the Orders.ShipAddress and Customers.Address, joined on the CustoemrID column in each table"
Write-Output ""
Write-Output "Additional tasks:"
Write-Output "Review both rgsubset-options.json examples in ./helper_scripts, as well as this documentation about using options files:"
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
