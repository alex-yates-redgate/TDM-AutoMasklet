# Test that this script is running as admin.
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$runningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $runningAsAdmin){
    Write-Warning "This script must be run as an administrator"
    break
}

# Config
$defaultInstallLocation = "$env:ProgramFiles\Red Gate\Test Data Manager"
$clisToInstall = @(
    "rganonymize",
    "rgsubset"
)

# Helper functions
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

Function Test-LatestVersion {
    param (
        [Parameter(Position=0,mandatory=$true)][ValidateSet("rganonymize","rgsubset")][string]$cli
    )
    # Reading XML blocks detailing the latest versions of rgsubset and rganonymize
    switch ($cli){
        "rganonymize" {$latestVersionXml = "https://redgate-download.s3.eu-west-1.amazonaws.com/?delimiter=/&prefix=EAP/AnonymizeWin64/"}
        "rgsubset" {$latestVersionXml = "https://redgate-download.s3.eu-west-1.amazonaws.com/?delimiter=/&prefix=EAP/SubsetterWin64/"}
    }
    $latestVersionData = (Invoke-WebRequest "$latestVersionXml").Content
    $latestsVersion = Find-LatestVersion $latestVersionData
    $currentVersion = (& $cli --version | Out-String).Trim()
    if ($currentVersion -like "*$latestsVersion*"){
        return $true
    }
    return $false
}

Function Get-ExistingCliLocation {
    param (
        [Parameter(Position=0,mandatory=$true)][ValidateSet("rganonymize","rgsubset")][string]$cli
    )
    $cliExe = (Get-Command $cli -ErrorAction SilentlyContinue).Source
    if ($cliExe){
        $cliLocation = Split-Path -parent $cliExe
        return $cliLocation
    }
    return $false
}

Function Install-TdmCli {
    # Performs a clean install of the designated Redgate Test Data Manager CLI
    param (
        [Parameter(Position=0,mandatory=$true)][ValidateSet("rganonymize","rgsubset")][string]$cli,
        [string]$installLocation = "$env:ProgramFiles\Red Gate\Test Data Manager"
    )

    # Config
    $downloadUrl = ""
    switch ($cli){
        "rganonymize" {$downloadUrl = "https://download.red-gate.com/EAP/AnonymizeWin64.zip"}
        "rgsubset" {$downloadUrl = "https://download.red-gate.com/EAP/SubsetterWin64.zip"}
    }
    $executablePath = "$installLocation\$cli.exe"
    $tempPath = "$installLocation\temp"
    $zipPath = "$tempPath\$cli.zip"
    $unzipPath = "$tempPath\${cli}_extracted"

    # Logging
    Write-Verbose "Installing: $cli"
    Write-Verbose "Config:"
    Write-Verbose "- Download URL: $downloadUrl"
    Write-Verbose "- Installation directory: $installLocation"
    Write-Verbose "- Temp files directory: $tempPath"

    # Check if tdmProgramFiles and tempPath already exist, if not, create them
    if (-not (Test-Path $installLocation)){
        Write-Verbose "Creating directory for executable at: $installLocation"
        New-Item -ItemType Directory -Path $installLocation | Out-Null
    }
    if (-not (Test-Path $tempPath)){
        Write-Verbose "Creating directory for temp files at: $tempPath"
        New-Item -ItemType Directory -Path $tempPath | Out-Null
    }
    # If zipPath already exists, delete it
    if (Test-Path $zipPath){
        Write-Verbose "Removing old zip file at: $zipPath"
        Remove-Item $zipPath -Force -Recurse | Out-Null
    }

    # Ensuring the install location is added to %PATH%
    if ($env:Path -like "*$installLocation*"){
        Write-Verbose "CLIs folder is already added to %PATH%"
    }
    else {
        Write-Verbose "CLIs folder is not added to %PATH%"
        Write-Verbose "- Adding $cli install location to PATH system variable."
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$installLocation", "Machine")
    }

    # Download a fresh file with the latest version of the code
    Write-Verbose "Downloading zip file containing latest version of $cli to: $zipPath"
    Invoke-WebRequest -Uri $downloadUrl -OutFile "$zipPath"
    
    # Extract the zip
    Write-Verbose "Extracting zip file to: $unzipPath"
    Add-Type -assembly "System.IO.Compression.Filesystem";
    [IO.Compression.Zipfile]::ExtractToDirectory($zipPath, "$unzipPath");

    # Find extracted CLI
    $extractedCli = (Get-ChildItem "$unzipPath").Name | Where-Object {$_ -like "*$cli*.exe"}

    # Delete old version, if exists
    if (Test-Path $executablePath){
        Write-Verbose "Removing old version of $cli"
        Remove-Item $executablePath -Force -Recurse | Out-Null
    }

    # Move and rename extracted CLI to $executablePath
    Write-Verbose "Copying new version of $cli to: $installLocation"
    Move-Item -Path "$unzipPath\$extractedCli" -Destination $executablePath

    # Delete temp files
    Write-Verbose "Removing temp files at: $tempPath"
    Remove-Item -Recurse -Force "$tempPath"

    if (Test-Path $executablePath){
        Write-Verbose "$cli is now installed at: $executablePath"
        return $true
    }
    else {
        Write-Error "Failed to install $cli"
        return $false   
    }
}

# Install!!!!
ForEach ($cli in $clisToInstall){
    $installLocation = Get-ExistingCliLocation -cli $cli
    if ($installLocation){
        # The CLI is already installed. Let's see if it's up to date.
        if (Test-LatestVersion $cli){
            Write-Output "$cli is already installed at $installLocation. It's up to date and available to PATH. No action necessary."
            $installRequired = $false
        }
        else {
            Write-Output "$cli is already installed, but not up to date. Will install latest version in existing location: $installLocation"
            $installRequired = $true
        }
    }
    else {
        Write-Output "$cli is not available to PATH. Will perform a fresh install to the default location: $defaultInstallLocation"
        $installLocation = $defaultInstallLocation
        $installRequired = $true
    }
    if ($installRequired){
        Write-Output "  Installing latest version of $cli to $installLocation..."
        if (Install-TdmCli $cli -installLocation $installLocation -Verbose) {
            Write-Output "  $cli installed successfully"
        }
        else {
            Write-Error "Failed to install $cli"
        }   
    }
}