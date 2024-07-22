# TDM-AutoMasklet
A Test Data Manager subsetting and anonymization worked example.

You can read more about this project in [a blog post by Steve Jones, available here](https://voiceofthedba.com/2024/07/10/up-and-running-quickly-with-test-data-manager/), and you can watch a 10 minute video about it here:

[![Steve Jones: Run Your Own Test Data Manager PoC in under 10 Minutes](https://img.youtube.com/vi/d-dlbVqU4R8/0.jpg)](https://www.youtube.com/watch?v=d-dlbVqU4R8)

## Purpose
This project exists as a minimal viable proof of concept for the subsetter and anonymize CLIs that come with Redgate Test Data Manager.

The run-auto-masklet.ps1 powershell script walks you through the steps required to subset and mask the PII in a sample database.

The ojective is to give users an easy way to get started with the CLIs, to understand their usage.

## System set up
You will need:
- A Windows machine to run this script and the subsetter/anonymize CLIs on. (May also work on Linux, but not tested.)
- [Git](https://git-scm.com/) installed on your Windows machine.
- A SQL Server instance to build some sample databases on.
- If these files are downloaded as a zip file, the [PowerShell Execution Policy](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.4) must be set to ByPass, or Unrestricted. If these files are cloned into a git repository, the PowerShell Execution Policy must be set to ByPass, Unrestricted, or RemoteSigned. (RemoteSigned is the default on Windows Servers). To manage your execution policy run the following PowerShell commands:

```
# To determine your execution policy:
Get-ExecutionPolicy

# To change your execution policy for a single session:
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process

# To permanently change your execution policy (must be executed as admin):
Set-ExecutionPolicy RemoteSigned
```

## Instructions
1. Open a PowerShell command prompt.
2. Clone the repo:
```
git clone https://github.com/alex-yates-redgate/TDM-AutoMasklet.git
```
3. Navigate into the directory (this is important):
```
cd TDM-AutoMasklet
```
4. Review the file .\run-auto-masklet.ps1. In particular, pay attention to the config section at the top. This section assumes your SQL Instance is running on localhost, and that you would like to output your files to C:/temp/auto-masklet. If you would like to use a different SQL Instance or output directory, update as appropriate.
5. Run the script, and follow the instructions. It will download, configure, and start a new trial for the TDM CLIs. Pay particular attention to each of the "Observe" and "Next" blocks, before continuing to the next stage:
```
.\run-auto-masklet.ps1
```

_Notes about the script:_
- _If you do not have dbatools or anonymize/subsetter installed already, you will ether need to execute run-auto-masklet.ps1 as admin (the first time) to perform the download/install._
- _When downloading and installing new software (initial runs and following software updates), the script will need a few minutes at the start to download and install everything. Subsequent runs will be much, much faster!_
- _Following installl, the script will attempt to authenticate anonymize and subset, this will open up a Redgate log-in page in your default web browser. You will need to log in for the script to continue._

## Next steps
After completing this worked example, I encourage you to review the following technical resources:
- Documentation: https://documentation.red-gate.com/testdatamanager/command-line-interface-cli
- Training: https://www.red-gate.com/hub/university/courses/test-data-management/cloning/overview/introduction-to-tdm

Can you subset and mask one of your own databases?

For more information, either contact your Redgate Account Manager, or email us at sales@red-gate.com.

## Work to do:
- Move this to an official Redgate repository.
- Remove dependency on Git
