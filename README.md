# TDM-AutoMasklet
A Test Data Manager subsetting and anonymization worked example

## Purpose
This project exists as a minimal viable proof of concept for the subsetter and anonymize CLIs that come with Redgate Test Data Manager.

The run-auto-masklet.ps1 powershell script steps you through a few the steps required to subset and mask the PII in a sample database.

The ojective is to give users an easy way to get started with the CLIs, to understand their usage.

## System set up
You will need:
- A Windows machine to run this script and the subsetter/anonymize CLIs on. (May also work on Linux, but not tested.)
- A SQL Server instance to build some sample databases on.

## Instructions
1. Open a PowerShell command prompt.
2. Clone the repo:
```
git clone https://github.com/alex-yates-redgate/TDM-AutoMasklet.git
```
3. Navigate into the directory:
```
cd TDM-AutoMasklet
```
4. Review the file .\run-auto-masklet.ps1. In particular, pay attention to the config section at the top. This section assumes your SQL Instance is running on localhost, and that you would like to output your files to C:/temp/auto-masklet. If you would like to use a different SQL Instance or output directory, update as appropriate.
5. Run the script, and follow the instructions. It will download, configure, and start a new trial for the TDM CLIs. Pay particular attention to each of the "Observe" and "Next" blocks, before continuing to the next stage:
```
.\run-auto-masklet.ps1
```

Note: If you do not have dbatools installed already, you will ether need to execute run-auto-masklet.ps1 as admin (the first time) so that it can install dbatools, or you will need to install dbatools separately, and then execute run-auto-masklet.ps1 afterwards.

## Next steps
After completing this worked example, I encourage you to review the following technical resources:
- Documentation: https://documentation.red-gate.com/testdatamanager/command-line-interface-cli
- Training: https://www.red-gate.com/hub/university/courses/test-data-management/cloning/overview/introduction-to-tdm

Can you subset and mask one of your own databases?

For more information, either contact your Redgate Account Manager, or email us at sales@red-gate.com.

## Work to do:
- Move this to an official Redgate repository.
