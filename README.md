# TDM-AutoMasklet
A Test Data Manager subsetting and anonymization worked example

## Purpose
This project exists as a minimal viable proof of concept for the subsetter and anonymize CLIs that come with Redgate Test Data Manager.

The run-auto-masklet.ps1 powershell script steps you through a few the steps required to subset and mask the PII in a sample database.

The ojective is to give users an easy way to get started with the CLIs, to understand their usage.

## System set up
You will need:
- A Windows machine to run this script and the subsetter/anonymize CLIs on.
- A SQL Server instance to build some sample databases on.
- The subsetter and anonymize CLIs. (Talk to your Redgate Account Manager to get hold of these.)
- The dbatools PowerShell module. The script will attempt to install it for you if you don't have it, but this requires that you run it as admin. More info about dbatools is available at dbatools.io

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
4. Run the script, and follow the instructions. Pay particular attention to each of the "Observe" and "Next" blocks, before continuing to the next stage:
.\run-auto-masklet.ps1

Note: If you do not have dbatools installed already, you will ether need to execute run-auto-masklet.ps1 as admin (the first time) so that it can install dbatools, or you will need to install dbatools separately, and then execute run-auto-masklet.ps1 afterwards.

## Work to do:
- Automate the install and configuration of anonymize/subset as part of the script.
- Move this to an official Redgate repository.