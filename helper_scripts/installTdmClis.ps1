param (
    $toolsPath = "$env:ProgramFiles\Red Gate\Test Data Manager"
)

# Reading XML blocks detailing the latest versions of subsetter and anonymize
$subsetterVersionsXml = (Invoke-WebRequest "https://redgate-download.s3.eu-west-1.amazonaws.com/?delimiter=/&prefix=EAP/SubsetterWin64/").Content
$anonymizeVersionsXml = (Invoke-WebRequest "https://redgate-download.s3.eu-west-1.amazonaws.com/?delimiter=/&prefix=EAP/AnonymizeWin64/").Content

function Find-Cli {
    param (
        [Parameter(Position=0,mandatory=$true)][ValidateSet("anonymize","subsetter")][string]$cli
    )
    if (Test-Path "$toolsPath\${cli}.exe"){
        return $toolsPath
    }

    $executable = (Get-Command $cli).Source
    if ($executable){
        $pathToExecutable = Split-Path -parent $executable
        return $pathToExecutable
    }
    else {
        return $false
    }
}



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
        [string]$toolsPath = "$env:ProgramFiles\Red Gate\Test Data Manager"
    )

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $runningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $runningAsAdmin){
        Write-Warning "This part of the script must be run as an administrator."
        return $false
    }

    $downloadUrl = ""
    switch ($cli){
        "anonymize" {$downloadUrl = "https://download.red-gate.com/EAP/AnonymizeWin64.zip"}
        "subsetter" {$downloadUrl = "https://download.red-gate.com/EAP/SubsetterWin64.zip"}
    }
    $executablePath = "$toolsPath\$cli.exe"
    $tempPath = "$toolsPath\temp"
    $zipPath = "$tempPath\$cli.zip"
    $unzipPath = "$tempPath\${cli}_extracted"

    # Logging
    Write-Verbose "      Installing: $cli"
    Write-Verbose "      Config:"
    Write-Verbose "      - Download URL: $downloadUrl"
    Write-Verbose "      - Installation directory: $toolsPath"
    Write-Verbose "      - Temp files directory: $tempPath"

    # Check if tdmProgramFiles and tempPath already exist, if not, create them
    if (-not (Test-Path $toolsPath)){
        Write-Verbose "      Creating directory for executable at: $toolsPath"
        New-Item -ItemType Directory -Path $toolsPath | Out-Null
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
    Write-Verbose "      Copying new version of $cli to: $toolsPath"
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

# Assume we don't need to install the CLIs
$subsetterInstalled = $false
$installSubsetter = $false
$anonymizeInstalled = $false
$installAnonymize = $false

# See if we can find existing CLIs
Write-Output "  Checking for existing installations of subsetter and anonymize..."
$subsetterPath = Find-Cli subsetter
if ($subsetterPath){
    Write-Output "  - subsetter found at: $subsetterPath"
    $subsetterInstalled = $true
}
else {
    Write-Output "  - subsetter not found."
    $installSubsetter = $true
    $subsetterPath = $toolsPath
}
$anonymizePath = Find-Cli anonymize
if ($anonymizePath){
    Write-Output "  - anonymize found at: $anonymizePath"
    $anonymizeInstalled = $true
}
else {
    Write-Output "  - anonymize not found."
    $installAnonymize = $true
    $anonymizePath = $toolsPath
}

# If necessary, adding the install location to %PATH%
if (($subsetterPath -like $toolsPath) -or ($anonymizePath -like $toolsPath)){
    # Check $toolsPath is added to %PATH%...
    if ($env:Path -like "*$toolsPath*"){
        Write-Output "  CLIs folder is already added to %PATH%"
    }
    else {
        # We need to install at least one CLI
        # Since it's not already available sumewhere, we'll install it to $toolsPath
        # We'll add $toolsPath to %PATH% so that the CLIs are available to the user
        Write-Output "  CLIs folder is not added to %PATH%"
        Write-Output "  - Adding $toolsPath to PATH system variable."
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $runningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $runningAsAdmin){
            Write-Warning "This part of the script must be run as an administrator."
            break
        }
        [Environment]::SetEnvironmentVariable("Path", $env:Path + ";$toolsPath", "Machine")
        # Refreshing the environment variables so that the new path is immediately available, without opening a new session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
}

# If available to %PATH%, testing to see if the CLIs are up to date
Write-Output "  Testing to see if the installed CLIs are up to date..."
# subsetter
if ($subsetterInstalled){
    Write-Output "    subsetter:"
    $latestsSubsetter = Find-LatestVersion $subsetterVersionsXml
    Write-Output "    - Latest:    $latestsSubsetter"
    $subsetterVersion = subsetter --version
    Write-Output "    - Installed: $subsetterVersion"
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
    Write-Output "    anonymize:"
    $latestsAnonymize = Find-LatestVersion $anonymizeVersionsXml
    Write-Output "    - Latest:    $latestsAnonymize"
    $anonymizeVersion = anonymize --version
    Write-Output "    - Installed: $anonymizeVersion"
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
    Write-Output "  Installing latest version of subsetter..."
    $installSuccessful = Install-TdmCli subsetter -toolsPath $subsetterPath -Verbose
    if ($installSuccessful -eq $false){
        Write-Error "Error installing the Redgate Test Data Manager CLIs. Please review the errors above."
        break
    }
}
if ($installAnonymize){
    Write-Output "  Installing latest version of anonymize..."
    $installSuccessful = Install-TdmCli anonymize -toolsPath $anonymizePath -Verbose
    if ($installSuccessful -eq $false){
        Write-Error "Error installing the Redgate Test Data Manager CLIs. Please review the errors above."
        break
    }
}