# Reading XML blocks detailing the latest versions of subsetter and anonymize
$subsetterVersionsXml = (Invoke-WebRequest "https://redgate-download.s3.eu-west-1.amazonaws.com/?delimiter=/&prefix=EAP/SubsetterWin64/").Content
$anonymizeVersionsXml = (Invoke-WebRequest "https://redgate-download.s3.eu-west-1.amazonaws.com/?delimiter=/&prefix=EAP/AnonymizeWin64/").Content

function Find-LatestVersion {
    param (
        [Parameter(Position=0,mandatory=$true)]$xml
    )
    # Parsing the XML to find all the available versions
    $versions = @()
    ($xml -Split "<Key>") | ForEach {
        $versions += ((($_ -split ".zip")[0] -split "_")[1]) 
    }

    # Remove duplicates
    $uniqueVersions = $versions | Select-Object -Unique

    # Sort versions, based on [System.Version]. More info: https://learn.microsoft.com/en-us/dotnet/api/system.version.parse?view=net-8.0
    $sortedVersions = $uniqueVersions | Sort-Object {
        [System.Version]::Parse($_)
    } -Descending

    # Return the biggest version
    return $sortedVersions[0]
}

Function Install-TdmCli {
    # Performs a clean install of the designated Redgate Test Data Manager CLI
    param (
        [Parameter(Position=0,mandatory=$true)][ValidateSet("anonymize","subsetter")][string]$cli,
        [string]$installLocation = "$env:ProgramFiles\Red Gate\Test Data Manager"
    )

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $runningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $runningAsAdmin){
        Write-Error "This part of the script must be run as an administrator."
        break
    }

    $downloadUrl = ""
    switch ($cli){
        "anonymize" {$downloadUrl = "https://download.red-gate.com/EAP/AnonymizeWin64.zip"}
        "subsetter" {$downloadUrl = "https://download.red-gate.com/EAP/SubsetterWin64.zip"}
    }
    $executablePath = "$installLocation\$cli.exe"
    $tempPath = "$installLocation\temp"
    $zipPath = "$tempPath\$cli.zip"
    $unzipPath = "$tempPath\${cli}_extracted"

    # Logging
    Write-Verbose "      Installing: $cli"
    Write-Verbose "      Config:"
    Write-Verbose "      - Download URL: $downloadUrl"
    Write-Verbose "      - Installation directory: $installLocation"
    Write-Verbose "      - Temp files directory: $tempPath"

    # Check if tdmProgramFiles and tempPath already exist, if not, create them
    if (-not (Test-Path $installLocation)){
        Write-Verbose "      Creating directory for executable at: $installLocation"
        New-Item -ItemType Directory -Path $installLocation | Out-Null
    }
    if (-not (Test-Path $tempPath)){
        Write-Verbose "      Creating directory for temp files at: $tempPath"
        New-Item -ItemType Directory -Path $tempPath | Out-Null
    }
    # If zipPath already exists, delete it
    if (Test-Path $zipPath){
        Write-Verbose "      Removing old zip file at: $zipPath"
        Remove-Item $zipPath -Force -Recurse | Out-Null
    }

    # Ensuring the install location is added to %PATH%
    if ($env:Path -like "*$installLocation*"){
        Write-Verbose "      CLIs folder is already added to %PATH%"
    }
    else {
        Write-Verbose "      CLIs folder is not added to %PATH%"
        Write-Verbose "      - Adding $cli install location to PATH system variable."
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$installLocation", "Machine")
    }

    # Download a fresh file with the latest version of the code
    Write-Verbose "      Downloading zip file containing latest version of $cli to: $zipPath"
    Invoke-WebRequest -Uri $downloadUrl -OutFile "$zipPath"
    
    # Extract the zip
    Write-Verbose "      Extracting zip file to: $unzipPath"
    Add-Type -assembly "System.IO.Compression.Filesystem";
    [IO.Compression.Zipfile]::ExtractToDirectory($zipPath, "$unzipPath");

    # Find extracted CLI
    $extractedCli = (Get-ChildItem "$unzipPath").Name | Where-Object {$_ -like "*$cli*.exe"}

    # Delete old version, if exists
    if (Test-Path $executablePath){
        Write-Verbose "      Removing old version of $cli"
        Remove-Item $executablePath -Force -Recurse | Out-Null
    }

    # Move and rename extracted CLI to $executablePath
    Write-Verbose "      Copying new version of $cli to: $installLocation"
    Move-Item -Path "$unzipPath\$extractedCli" -Destination $executablePath

    # Delete temp files
    Write-Verbose "      Removing temp files at: $tempPath"
    Remove-Item -Recurse -Force "$tempPath"

    if (Test-Path $executablePath){
        Write-Verbose "      $cli is now installed at: $executablePath"
        return $true
    }
    else {
        Write-Error "Failed to install $cli"
        return $false   
    }
}

$defaultInstallLocation = "$env:ProgramFiles\Red Gate\Test Data Manager"
$installSubsetter = $false
$subsetterInstalled = $false
$subsetterInstallLocation = $defaultInstallLocation
$installAnonymize = $false
$anonymizeInstalled = $false
$anonymizeInstallLocation = $defaultInstallLocation

# Testing to see if the CLIs are already available to %PATH%
Write-Output "    Testing which CLIs are already installed..."
# subsetter
$subsetterExe = (Get-Command subsetter).Source
if ($subsetterExe){
    $subsetterInstallLocation = Split-Path -parent $subsetterExe
    Write-Output "    - subsetter already installed at: $subsetterInstallLocation" 
    $subsetterInstalled = $true   
}
else {
    Write-Output "    - subsetter not available to %PATH%"
    $installSubsetter = $true
}
# anonymize
$anonymizeExe = (Get-Command anonymize).Source
if ($anonymizeExe){
    $anonymizeInstallLocation = Split-Path -parent $anonymizeExe
    Write-Output "    - anonymize already installed at: $anonymizeInstallLocation" 
    $anonymizeInstalled = $true   
}
else {
    Write-Output "    - anonymize not available to %PATH%"
    $installAnonymize = $true
}

# If already available to %PATH%, testing to see if the CLIs are up to date
Write-Output "    Testing to see if the installed CLIs are up to date..."
# subsetter
if ($subsetterInstalled){
    Write-Output "      subsetter:"
    $latestsSubsetter = Find-LatestVersion $subsetterVersionsXml
    Write-Output "      - Latest:    $latestsSubsetter"
    $subsetterVersion = subsetter --version
    Write-Output "      - Installed: $subsetterVersion"
    if ($subsetterVersion -like "*$latestsSubsetter*"){
        Write-Output "      - UP TO DATE"
    }
    else {
        Write-Output "      - OUT OF DATE"
        $installSubsetter = $true
    }
}
# anonymize
if ($anonymizeInstalled){
    Write-Output "      anonymize:"
    $latestsAnonymize = Find-LatestVersion $anonymizeVersionsXml
    Write-Output "      - Latest:    $latestsAnonymize"
    $anonymizeVersion = anonymize --version
    Write-Output "      - Installed: $anonymizeVersion"
    if ($anonymizeVersion -like "*$latestsAnonymize*"){
        Write-Output "      - UP TO DATE"
    }
    else {
        Write-Output "      - OUT OF DATE"
        $installAnonymize = $true
    }
}

# If required, installing the CLIs
if ($installSubsetter){ 
    Write-Output "    Installing latest version of subsetter..."
    Install-TdmCli subsetter -installLocation $subsetterInstallLocation -Verbose
}
if ($installAnonymize){
    Write-Output "    Installing latest version of anonymize..."
    Install-TdmCli anonymize -installLocation $anonymizeInstallLocation -Verbose
}

if ($installAnonymize -or $installSubsetter){
    Write-Output "    To start a free trial of Redgate Test Data Manager, open a new terminal window and run:"
    Write-Output "      subsetter auth --agree-to-eula --start-trial"
    Write-Output "    For more information about licensing/activating your software:"
    Write-Output "      https://documentation.red-gate.com/testdatamanager/getting-started/licensing/activating-your-license"    
}