# TDM-AutoMasklet
A Test Data Manager subsetting and anonymization worked example.

You can read more about this project in [a blog post by Steve Jones, available here](https://voiceofthedba.com/2024/07/10/up-and-running-quickly-with-test-data-manager/), and you can watch a 10 minute video about it here:

[![Steve Jones: Run Your Own Test Data Manager PoC in under 10 Minutes](https://img.youtube.com/vi/d-dlbVqU4R8/0.jpg)](https://www.youtube.com/watch?v=d-dlbVqU4R8)

## Purpose
This project exists as a minimal viable proof of concept for the rgsubsetter and rganonymize CLIs that come with Redgate Test Data Manager.

The run-auto-masklet.ps1 powershell script walks you through the steps required to subset and mask the PII in a sample database.

The ojective is to give users an easy way to get started with the CLIs, and to understand their usage.

## System set up
You will need:
- A Windows machine to run this script and the rgsubsetter/rganonymize CLIs on. (May also work on Linux, but not tested.)
- A SQL Server instance to build some sample databases on.
- If these files are downloaded as a zip file, the [PowerShell Execution Policy](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.4) must be set to ByPass, or Unrestricted.
- If these files are cloned into a git repository, the PowerShell Execution Policy must be set to ByPass, Unrestricted, or RemoteSigned. (RemoteSigned is the default on Windows Servers). To manage your execution policy run the following PowerShell commands:

```
# To determine your execution policy:
Get-ExecutionPolicy

# To change your execution policy for a single session:
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process

# To permanently change your execution policy (must be executed as admin):
Set-ExecutionPolicy RemoteSigned
```

## Instructions
1. Get the code either by cloning the repo (prefered), or by downloding and extracting the zip file (if it is not practical to use git to clone the repo):
    1. **To clone the repo:** Ensure ([git is installed](https://git-scm.com/)). Then open a PowerShell command prompt and run the following command: 
    ```
       git clone https://github.com/alex-yates-redgate/TDM-AutoMasklet.git
    ```
    2. **To download the code as a zip file:** Click the green "<> Code" button [on the home page for this repo](https://github.com/alex-yates-redgate/TDM-AutoMasklet), and select "Download ZIP". Then extract the zip file as you see fit. Finally, review the note under [System Setup (above)](https://github.com/alex-yates-redgate/TDM-AutoMasklet?tab=readme-ov-file#system-set-up) about PowerShell Execution Policies, and ensure the PowerShell Execution Policy on your machine is appropriately configured.
2. Review the file [.\run-auto-masklet.ps1](https://github.com/alex-yates-redgate/TDM-AutoMasklet/blob/main/run-auto-masklet.ps1). In particular, pay attention to the "param" (parameters) section at the top. This section assumes your SQL Instance is running on localhost, and that you would like to output your files to C:/temp/auto-masklet. (This directory will be cleaned and recreated each time you run the script). If you would like to use a different SQL Instance or output directory, update the config as appropriate.
3. Navigate to the directory you copied the code to, and then run the script in a PowerShell window. The script will download, configure, and start a new trial for the TDM CLIs. Note, during licence/trial activation, a web browser may open, and you may be required to log into the Redgate licencing portal.

Using the default sample databases (run script without options)
```
cd TDM-AutoMasklet      # Navigate to the directory you cloned the repo to/extracted the zip file to
.\run-auto-masklet.ps1  # Run the default script
```

Using a custom backup file (run script with options)
```
cd TDM-AutoMasklet      # Navigate to the directory you cloned the repo to/extracted the zip file to
.\run-auto-masklet.ps1 -backupPath "path_to_backup_file" -databaseName "database_name" # Run the script with options
```
4. If you ran the script without a custom backup file, it will create a couple of sample databases for you (by default, Northwind_FullRestore and Northwind_Subset). If these databases already exist, they will be dropped and recreated.<br />
If you ran the script with a custom backup file, it will create the databases from your provided backup file (database_name_FullRestore and database_name_Subset).<br />
The script will then pause and walk you through each of the major steps required to subset and anonymize a database. Follow the instructions, and pay particular attention to each of the "Observe" and "Next" blocks, before continuing to the next stage.

_Notes about the script:_
- _If you do not have dbatools or rganonymize/rgsubsetter installed already, you will need to execute run-auto-masklet.ps1 as admin (the first time) to perform the download/install._
- _When downloading and installing new software (initial runs and following software updates), the script will need a few minutes at the start to download and install everything. Subsequent runs will be much, much faster!_

## Next steps
After completing this worked example, I encourage you to review the following technical resources:
- Documentation:  https://documentation.red-gate.com/testdatamanager/command-line-interface-cli
- Training:       https://www.red-gate.com/hub/university/courses/test-data-management/cloning/overview/introduction-to-tdm

Can you subset and mask one of your own databases?

For more information, either contact your Redgate Account Manager, or email us at sales@red-gate.com.

## Subsetting Options File (rgsubset-options-northwind.json) Description
This file defines how rgsubset will perform the subset on the target database. The file defines a subset by filter query, with dbo.Orders as the starting table and OrderId < 10260. Furthermore, the includeTableRowsThreshold is set to 1. By default the value is 300, so by including this parameter we are telling rgsubset to forcibly bring in any tables with 1 or less rows, which is none. Without this parameter the subsetting can seem to perform unexpectedly on very small databases, like the one in this example. The dbo.Customers table should bring through around 12 rows aswell, but without this parameter rgsubset will populate the dbo.Customers table with all it's original data.

## Work to do:
- Move this to an official Redgate repository.
