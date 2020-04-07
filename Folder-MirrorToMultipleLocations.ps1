#
#     written by:   Steve Geall
#           date:   July 2017
#
#       synopsis:   Monitor master folder (including subfolders) and sync any
#                   changes to multiple remote shares using RoboCopy.
#
#   requirements:   PowerShell v2+
#
#    description:   Sets up a FileSystemWatcher on "mediafolder" that monitors this directory and all subdirectories
#                   for the created/changed/renamed/deleted file events only (not directory events). This happens every
#                   x amount of seconds (can be set in variables below).
#                   When an event is noticed, it is processed and if OK a respective RoboCopy command is added to
#                   an array. (this is because if 100 files are copied in we don't want to run a RoboCopy mirror 100
#                   times on the same folder unnecessarily).
#                   Every x cycles of the event monitoring loop (can be set in variables below), this array
#                   is checked and if there are any rows, they are executed as RoboCopy commands. This mirrors the "mediafolder"
#                   to all remote folders and writes to the log file.
#
#          usage:   Create a Scheduled Task...
#                   - Name      [media sync]
#                   - General   [Run whether user logged on or not (SYSTEM or service account)]
#                               [Run with highest privileges]
#                   - Triggers  [Daily @ 4:30am] because we don't want the script being restarted during the day while processing something
#                   - Actions   [Start a Program]
#                               [program = powershell.exe]
#                               [arguments = -ExecutionPolicy Bypass "<path to script>\media_sync.ps1"]
#                   - Settings  [allow taks to be run on demand]
#                               [if the running task does not end when requested, force it to stop]
#                               [if the task is already running, then the following rule applies: Stop the existing instance]
#
#                   Create a batch file for manually starting/restarting the scheduled task...
#                       @echo off
#                       setlocal
#                       SET AREYOUSURE=N
#                       echo About to kill all powershell.exe processes and run the scheduled task "media sync"
#                       :PROMPT
#                       SET /P AREYOUSURE=Are you sure (Y/[N])?
#                       IF /I "%AREYOUSURE%" NEQ "Y" GOTO END
#                       echo You selected, Y...
#                       taskkill /F /IM powershell.exe /T
#                       schtasks /Run /TN "media sync"
#                       :END
#                       echo Exiting...
#
#                   Encrypting a password (if you want to add a remote path or update the password)...
#                   - Create a powershell script with below code:                 
#                       $password = read-host -prompt "Enter your Password"
#                       write-host "$password is password"
#                       $KeyFile = "$PSScriptroot\AES.key"
#                       $KeyObj = New-Object Byte[] 16   # You can use 16, 24, or 32 for AES
#                       Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($KeyObj)
#                       $KeyObj | out-file $KeyFile
#                       $Key = Get-Content $KeyFile
#                       $secure = ConvertTo-SecureString $password -force -asPlainText
#                       $bytes = ConvertFrom-SecureString $secure -key $key
#                       $bytes | out-file .\securepassword-with-key.txt
#                   - This encrypts your password and writes it to securepassword-with-key.txt with a key file AES.key
#                   - See the code below at "### set access to remote shares" for reading in the encrypted password
#
#          notes:   - Handles file deletions when the folder the file was deleted from still exists, but not
#                     if the folder is also deleted (can't RoboCopy mirror a folder that doesn't exist).
#                     Perhaps handle this by running a RoboCopy Mirror on the ENTIRE ..\media folder once per
#                     night? This process will take some time to compare the huge ..\media folder but will ensure
#                     everything is all mirrored up OK. Or use PowerShell Remove-Item to delete the folders from the
#                     remote paths.
#                   - Can't use the /mon or /mot RoboCopy switches as the monitored master directory is too large. RoboCopy
#                     does a compare of the directories EVERY time the /mon or /mot time is met. This is why we're using
#                     .net FileSystemWatcher to trigger events.
#
#
#
#   must restart script to pick up any changes (via task scheduler, end the task, then run it again)
#

$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition # in case any PS versions older than v3

### ENSURE BELOW VARIABLES ARE OK  

    ### set window name
    $host.ui.RawUI.WindowTitle = "media sync v0.1"

    ### monitored master path
    Set-Variable -name mediafolder -value "D:\media" -Scope Global # no trailing slash

    ### paths for robocopy to mirror/sync to
    Set-Variable -name remotePaths -value @("\\server02\media","\\server03\media") -Scope Global # no trailing slashes

    ### set access to remote shares
    $encryptedPassword02 = "123456789123456789123456789123456789123456789123456789123456789123456789"
    $KeyFile02 = "$PSScriptroot\AES02.key"
    $key02 = Get-Content $KeyFile02
    $username02 = "server02\name"
    $password02 = ($encryptedPassword02 | ConvertTo-SecureString -Key $key02)
    $helper02 = new-object -typename System.Management.Automation.PSCredential -argumentlist $username02, $password02
    $pass02 = $helper02.GetNetworkCredential().Password
    (NET USE \\server02\media /user:$username02 $pass02) | out-null

    $encryptedPassword03 = "7894561237894561237894561234789456123789456123789456123789456123789456123"
    $KeyFile03 = "$PSScriptroot\AES03.key"
    $key03 = Get-Content $KeyFile03
    $username03 = "server03\name"
    $password03 = ($encryptedPassword03 | ConvertTo-SecureString -Key $key03)
    $helper03 = new-object -typename System.Management.Automation.PSCredential -argumentlist $username03, $password03
    $pass03 = $helper03.GetNetworkCredential().Password
    (NET USE \\server03\media /user:$username03 $pass03) | out-null

    

    ### check every (seconds) - minimum 5 seconds
    Set-Variable -name checkEverySeconds -value 15

    ### robo wait cycle (number of check every's to go through before processing robocopy commands)
    ### checks for any robocopy jobs waiting every (this value multiplied by the checkeveryseconds value) seconds
    Set-Variable -name roboWaitCycle -value 4

    ### foldersize stabilise time (seconds)
    ### folder size must be stable for this many seconds before processing
    Set-Variable -name stableTime -value 2 -Scope Global

    ### set debug level between 1 (low) and 3 (high) - must restart script to pick up any changes
    Set-Variable -name debugLevel -value 2 -Scope Global

    ### set robocopy parameters
    Set-Variable -name robocopyParams -value "/MIR /XO /FFT /Z /MT /XX /R:4 /W:2" -Scope Global
        # /mir Mirrors a directory tree (equivalent to /e plus /purge).
        # /xo Excludes older files.
        # /fft Assumes FAT file times (two-second precision).
        # /z Copies files in Restart mode.
        # /XX eXclude "eXtra" files and dirs (present in destination but not source)
        #     This will prevent any deletions from the destination. (this is the default)
        # /MT[:N] Creates multi-threaded copies with N threads. N must be an integer between 1 and 128. The default value for N is 8. The /MT parameter cannot be used with the /IPG and /EFSRAW parameters. Redirect output using /LOG option for better performance.
        # /r:<N> Specifies the number of retries on failed copies. The default value of N is 1,000,000 (one million retries).
        # /w:<N> Specifies the wait time between retries, in seconds. The default value of N is 30 (wait time 30 seconds).
###




# ensure checkevery isn't less than 5 seconds
If ($checkEverySeconds -lt 5) {
    $checkEverySeconds = 5
}

# ensure debugLevel isn't greater than 3
If ($debugLevel -gt 3) {
    $debugLevel = 3
}

### global variable for array to store robocopy commands
Set-Variable -name roboCommands -value @() -Scope Global

### global variables for event counts
Set-Variable -name eventCount -value 0 -Scope Global
Set-Variable -name roboCount -value 0 -Scope Global
Set-Variable -name roboWait -value 0 -Scope Global

### global variables for writing lines to host based on debug level
Set-Variable -name d -value 0 -Scope Global
Set-Variable -name debugMsg -value "" -Scope Global

### log location
$logdir = "$PSScriptroot\log"
if(!(Test-Path -Path $logdir )){
    New-Item -ItemType directory -Path $logdir | Out-Null
}
Set-Variable -name LogPath -value "$logdir\media_sync_log_" -Scope Global # include trailing underscore, script will add datestamp

Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -value "top of script" 

### debug function
function global:debug {
    param (
        [string]$d,
        [string]$debugMsg,
        [string]$col,
        [string]$log
    )
    If ($col) {
        If ($d -le $debugLevel) {
            Write-Host "$(Get-Date -format 'ddd.HH:mm:ss:fff'), $debugMsg" -ForegroundColor $col
        }
    } Else {
        If ($d -le $debugLevel) {
            Write-Host "$(Get-Date -format 'ddd.HH:mm:ss:fff'), $debugMsg" -ForegroundColor White
        }
    }
    If ($log) {
        Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "DEBUG ($debugLevel): $debugMsg"
    }
}


### scriptblock used when a file is created/changed/renamed/deleted
    $SyncFolder = {
        
        $global:eventCount++

        #write-host "here comes all objects for event"
        #$event | Select-Object * | Write-Host
        #write-host "here comes all eobjects for evntargs"
        #$eventArgs | Select-Object * | Write-Host

        debug 2 "   DEBUG :: -----------------" "Yellow"

        # set subfolder based on whether a file or directory event
        If (!(Test-Path -LiteralPath $Event.SourceEventArgs.FullPath -pathtype container)) { 
            debug 2 "   DEBUG :: this is a FILE event ($($Event.SourceEventArgs.Name)) [event id=$($Event.EventIdentifier)]" "Yellow" "log"
            #$subfolder = $path::GetFileName($path::GetDirectoryName($event.SourceEventArgs.FullPath)) #this is if event was from a file
            $fullfolderpath = [System.IO.Path]::GetDirectoryName($Event.SourceEventArgs.FullPath)
            $subfolder = $fullfolderpath.Replace($mediafolder,"")
        } Else {
            # is a folder event, but we have filtered these out at filesystemwatcher so don't get any folder events anyway
            debug 2 "   DEBUG :: this is a FOLDER event ($($Event.SourceEventArgs.Name)) [event id=$($Event.EventIdentifier)]" "Yellow" "log"
            debug 2 " PROCESS :: stop processing this event." "" "log"
            Write-Host "--------------------------"
            Return
        }

        $fullpath = $Event.SourceEventArgs.FullPath
        
        $changeType = $Event.SourceEventArgs.ChangeType
        If (!$changeType) {
            $changeType = $Event.SourceIdentifier # use changetype (sourceidentifier)
        }

        $timeStamp = ($Event.TimeGenerated).ToString("HH:mm:ss:fff")

        $eventID = $($Event.EventIdentifier)
        
        debug 2 "   DEBUG :: timeStamp      = $timeStamp" "Yellow"
        debug 2 "   DEBUG :: eventID        = $eventID" "Yellow"
        debug 2 "   DEBUG :: changeType     = $changeType" "Yellow"
        debug 2 "   DEBUG :: fullpath       = $fullpath" "Yellow"
        debug 2 "   DEBUG :: fullfolderpath = $fullfolderpath" "Yellow"
        debug 2 "   DEBUG :: subfolder      = $subfolder" "Yellow"

        Write-Host "**************************"
        debug 1 "   EVENT :: $changeType, (folder = $subfolder) [eventTime = $timeStamp] [event id=$eventID]" "White"

        If ($fullfolderpath -eq $mediafolder) {
            # fullfolderpath same as mediafolder DO NOT WANT TO INITIATE THIS MIRROR, would take a LONG time (media folder in excess of 150,000 folders)
            debug 1 "    INFO :: fullfolderpath and mediafolder are the same, do NOT want to mirror entire media folder, this takes a long time and is handled in overnight process anyway" "Blue" "log"
            debug 1 " PROCESS :: stop processing this event." "" "log"
            Write-Host "--------------------------"
            Return
         }

        # check if fullfolderpath already in roboCommands array awaiting processing
        debug 3 "   DEBUG :: check if fullfolderpath is already in the roboCommands array" "Yellow"
        debug 3 "   DEBUG :: roboCommands array count=$($global:roboCommands.Count)" "Yellow"
        If($global:roboCommands.Count -gt 0) {
            If ($global:roboCommands -like "*$fullfolderpath*") {
                debug 1 "    INFO :: folder ($fullfolderpath) already in roboCommands array awaiting processing, no need to add again." "Blue" "log"
                debug 1 " PROCESS :: stop processing this event." "" "log"
                Write-Host "--------------------------"
                Return
            }
        }
        
        <#
        # stop processing event if changetype is a deletion
        If ($changeType -eq "Deleted") {
            debug 2 "   DEBUG :: return, not handling Deleted events yet" "Yellow"
            debug 2 "   DEBUG :: stop processing this event." "White"
            Return
        }
        #>
        
        # reset roboWait variable to 0
        debug 3 "   DEBUG :: (roboWait: $global:roboWait) " "Yellow"
        $global:roboWait = 0
        debug 3 "   DEBUG :: adding a new file to be robocopied, reset roboWait variable to 0 (roboWait: $global:roboWait) " "Yellow"
        


        # loop until foldersize is >0 and stable for $stableTime seconds
        debug 3 "   DEBUG :: loop until foldersize is >0 and stable for $stableTime seconds" "Yellow"
        
        If (!(Test-Path -Path $fullfolderpath)) { # check folder still exists before hitting loops, otherwise return
            debug 1 "    INFO :: fullfolderpath ($fullfolderpath) no longer exists, return." "Blue" "log"
            debug 1 " PROCESS :: stop processing this event." "" "log"
            Write-Host "--------------------------"
            Return
        }

        $sizeCheckTimeoutAt = 10 # in seconds (approximately)
        $sizeTimeout = 0
        # loop until folder size larger than 1 byte
        Do {
            Start-Sleep -MilliSeconds 100
            $subfolderSize = (Get-ChildItem $fullfolderpath -Recurse -Force | Measure-Object -Property Length -Sum ).Sum
            $sizeTimeout = $sizeTimeout + 0.1
            debug 3 "   DEBUG :: subfoldersize=$subfolderSize" "Yellow"
            debug 3 "   DEBUG :: sizetimeout=$sizeTimeout" "Yellow"
        } Until (($subfolderSize -gt 1) -Or ($sizeTimeout -ge $sizeCheckTimeoutAt))
        
        If ($sizeTimeout -ge $sizeCheckTimeoutAt) {
            debug 1 "    INFO :: folder size timeout, ($subfolder) size was never larger than 1 byte" "Blue" "log"
            debug 1 " PROCESS :: stop processing this event." "" "log"
            Write-Host "--------------------------"
            Return
        }

        # check folder still exists before hitting loops, otherwise return
        If (!(Test-Path -Path $fullfolderpath)) { 
            debug 1 "    INFO :: fullfolderpath ($fullfolderpath) no longer exists, return." "Blue" "log"
            debug 2 " PROCESS :: stop processing this event." "" "log"
            Write-Host "--------------------------"
            Return
        }

        # loop until folder size stable
        debug 1 "    INFO :: wait until folder size stable ($stableTime seconds)..." "Blue"
        $subfolderSizePrev = 0
        $subfolderSizeCurr = 1
        $stablefor = 0
        $loopTimeout = 0
        While (($subfolderSizePrev -ne $subfolderSizeCurr) -Or ($stablefor -le $stableTime)) {
            $subfolderSizePrev = (Get-ChildItem $fullfolderpath -Recurse -Force | Measure-Object -Property Length -Sum ).Sum
            debug 3 "   DEBUG :: subfolderSizePrev=$subfolderSizePrev" "Yellow"
            Start-Sleep 1
            $subfolderSizeCurr = (Get-ChildItem $fullfolderpath -Recurse -Force | Measure-Object -Property Length -Sum ).Sum
            debug 3 "   DEBUG :: subfolderSizeCurr=$subfolderSizeCurr" "Yellow"
            If ($subfolderSizePrev -eq $subfolderSizeCurr) {
                debug 3 "   DEBUG :: foldersize stable, for $stablefor seconds now (waiting until $stableTime sec)." "Yellow"
                $stablefor++
            } Else {
                debug 3 "   DEBUG :: foldersize not stable yet, or changed, stable time is 0sec." "Yellow"
                $stablefor = 0
            }
            $loopTimeout++ # just for sanity, timeout after ~120 seconds
            If ($loopTimeout -gt 120) {
                debug 1 "    INFO :: timed out in loop waiting for folder size to stabilise." "Blue" "log"
                debug 1 " PROCESS :: stop processing this event." "" "log"
                Write-Host "--------------------------"
                Return
            }
        }
 
        # reset logline string to blank
        $logline = ""

        # ensure folder exists
        debug 3 "   DEBUG :: (folder = $subfolder), [ensure folder exists...]" "Yellow"
        If (Test-Path -Path $fullfolderpath) {
			$folderexistsTF = "True"
		} Else {
			$folderexistsTF = "False"
        }
        debug 3 "   DEBUG :: (folder = $subfolder), [folderexistsTF = $folderexistsTF]" "Yellow"
                       
        # start building logline string
        $logline = "$logline-------------------------`r`n"
        $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), FileSystemWatcher update noticed...`r`n"
        $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [event count = $eventCount]`r`n"
        $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [event = $changeType @ $timeStamp]`r`n"
        $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [fullpath = ($fullpath)]`r`n"
        $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [fullfolderpath = ($fullfolderpath)]`r`n"
		$logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [subfolder = ($subfolder)]`r`n"
		$logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [folder exists = $folderexistsTF]`r`n"
        
        debug 2 "   DEBUG :: ok, foldersize stable, folder exists, continue processing this event..." "Yellow"
        
        debug 3 "  FOLDER :: $changeType, (folder = $subfolder) [folderexistsTF = $folderexistsTF, eventTime = $timeStamp]"
		
        # Process file based on event type (created/changed/renamed/deleted)
        If ($changeType -eq "Created" -Or $changeType -eq "Changed" -Or $changeType -eq "ExistingFile" -Or $changeType -eq "Renamed" -Or $changeType -eq "Deleted") {
            debug 3 "   DEBUG :: changetype matches, process it, ($changeType)" "Yellow" "log"
            If (Test-Path -Path $fullfolderpath) {
                debug 1 " PROCESS :: $changeType, (folder = $subfolder) [add arguments to roboCommands array for RoboCopy mirroring...]"
                $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [add arguments to roboCommands array for RoboCopy mirroring...]`r`n"
                ForEach ($remotePath in $remotePaths) {
                    debug 2 "   DEBUG :: adding line to roboCommands array - ""$mediafolder$subfolder"" ""$remotePath$subfolder"" $robocopyParams" "Yellow"
                    $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),  [args = adding line to roboCommands array - ""$mediafolder$subfolder"" ""$remotePath$subfolder"" $robocopyParams]`r`n"
                    
                    $robocmdTempFile = "$PSScriptroot\$(Get-Random).robocmd"
                    $commandToAdd = " ""$mediafolder$subfolder"" ""$remotePath$subfolder"" $robocopyParams"
                    $global:roboCommands += (,($commandToAdd,$robocmdTempFile))
                    #$global:roboCommands += " ""$mediafolder$subfolder"" ""$remotePath$subfolder"" $robocopyParams"
                    Add-Content $robocmdTempFile " ""$mediafolder$subfolder"" ""$remotePath$subfolder"" $robocopyParams"
                    debug 3 "   DEBUG :: robocommands array is currently..." "Yellow"
                    ForEach ($line in $global:roboCommands){
                        debug 3 "            array line - $line" "Gray"
                    }
                }
            } Else {
                debug 1 " PROCESS :: $changeType, ($subfolder) [fullfolderpath no longer exists]"
                $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'),   [***fullfolderpath no longer exists]`r`n"    
            }
        } Else {
            debug 1 " PROCESS :: $changeType, ($subfolder) [not a changetype set to be processed]"
            $logline = "$logline$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), $changeType, ($subfolder) [not a changetype set to be processed]`r`n"
        }

        # complete logline string and write to file
		Write-Host "--------------------------"
        $logline = "$logline-------------------------"
        Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -value $logline

	}#<--end syncfolder scriptblock


### Create a fileWatcher that will monitor the directory and add its attributes
$fileWatcher = New-Object System.IO.FileSystemWatcher
$fileWatcher.Path = $mediafolder
$fileWatcher.InternalBufferSize = 16384
$fileWatcher.Filter = "*.*"
$fileWatcher.IncludeSubdirectories = $true
$fileWatcher.EnableRaisingEvents = $true
$fileWatcher.NotifyFilter = [System.IO.NotifyFilters]::FileName # only raise event if a file event occurs
#$fileWatcher.NotifyFilter = [System.IO.NotifyFilters]::FileName ,
#							[System.IO.NotifyFilters]::DirectoryName
                                        
### If a delegate has already been added to the FileWatchers for that event remove it and add the new one.
If (((Get-EventSubscriber -ErrorAction SilentlyContinue -SourceIdentifier "FileChanged").SourceIdentifier) -eq "FileChanged") {
    Get-EventSubscriber -SourceIdentifier "FileChanged" | Unregister-Event
    $ChangedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Changed -SourceIdentifier FileChanged -Action $SyncFolder
} Else {
    $ChangedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Changed -SourceIdentifier FileChanged -Action $SyncFolder
}
If (((Get-EventSubscriber -ErrorAction SilentlyContinue -SourceIdentifier "FileCreated").SourceIdentifier) -eq "FileCreated") {
    Get-EventSubscriber -SourceIdentifier "FileCreated" | Unregister-Event
    $CreatedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Created -SourceIdentifier FileCreated -Action $SyncFolder
} Else {
    $CreatedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Created -SourceIdentifier FileCreated -Action $SyncFolder
}
If (((Get-EventSubscriber -ErrorAction SilentlyContinue -SourceIdentifier "FileDeleted").SourceIdentifier) -eq "FileDeleted") {
    Get-EventSubscriber -SourceIdentifier "FileDeleted" | Unregister-Event
    $DeletedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Deleted -SourceIdentifier FileDeleted -Action $SyncFolder
} Else {
    $DeletedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Deleted -SourceIdentifier FileDeleted -Action $SyncFolder
}
If (((Get-EventSubscriber -ErrorAction SilentlyContinue -SourceIdentifier "FileRenamed").SourceIdentifier) -eq "FileRenamed") {
    Get-EventSubscriber -SourceIdentifier "FileRenamed" | Unregister-Event
    $RenamedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Renamed -SourceIdentifier FileRenamed -Action $SyncFolder
} Else {
    $RenamedEvent = Register-ObjectEvent -InputObject $fileWatcher -EventName Renamed -SourceIdentifier FileRenamed -Action $SyncFolder
}

Function RoboCopyExitCodeMeaning ($code) {
    Switch ($code) {
        0 {Return "No Change"}
        1 {Return "OKCOPY"}
        2 {Return "XTRA"}
        3 {Return "OKCOPY and XTRA"}
        4 {Return "MISMATCHES"}
        5 {Return "OKCOPY and MISMATCHES"}
        6 {Return "MISMATCHES and XTRA"}
        7 {Return "OKCOPY and MISMATCHES and XTRA"}
        8 {Return "FAIL"}
        9 {Return "OKCOPY and FAIL"}
        10 {Return "FAIL and XTRA"}
        11 {Return "OKCOPY and FAIL and XTRA"}
        12 {Return "FAIL and MISMATCHES"}
        13 {Return "OKCOPY and FAIL and MISMATCHES"}
        14 {Return "FAIL and MISMATCHES and XTRA"}
        15 {Return "OKCOPY and FAIL and MISMATCHES and XTRA"}
        16 {Return "***FATAL ERROR***"}
        default {Return "unknown exit code from RoboCopy"}
    }
}



### Start log #################################################################
    write-host "----------------------------------" -ForegroundColor Cyan    
    write-host " media sync started!" -ForegroundColor Cyan
    write-host " debug level set to: $debugLevel (of 3)" -ForegroundColor Cyan
    write-host "----------------------------------" -ForegroundColor Cyan
    $logStart = "`r`n*****************************`r`n*****************************`r`n*  media sync  *`r`n*      monitor STARTED      *`r`n*   $(Get-Date -format 'dd-MMM-yyyy HH:mm:ss')    *`r`n*****************************`r`n* Monitoring:`r`n* -----------`r`n"
    $logStart = "$logStart* $mediafolder (incl. subfolders)`r`n*`r`n"
    $logStart = "$logStart* Syncing to:`r`n* -----------`r`n"
    ForEach($remotepath in $remotepaths) {
        $logStart = "$logStart* $remotepath`r`n"
    }
    $logStart = "$logStart*****************************`r`npid=$PID`r`n*****************************`r`n*****************************`r`n"
    Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -value $logStart 


### Initial clean up ##########################################################
### look for any existing .robolog and .robocmd files (perhaps remain from previous processing but didn't complete for whatever reason)

    # write any missed robo logs to main log file (all .robolog files)
    Get-ChildItem "$PSSCriptroot" -Filter *.robolog | 
    Foreach-Object {
        $robologTemp = Get-Content $_.FullName
        ForEach ($roboline in $robologTemp) {
            Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), (from previous instance missed robo log) $roboline `n"
        }    
        Remove-Item -Path $_.FullName -force
    }
    # perform any missed/incomplete robo mirrors (all .robocmd files)
    Get-ChildItem "$PSSCriptroot" -Filter *.robocmd | 
    Foreach-Object {
        $robocmdTemp = Get-Content $_.FullName
        ForEach ($robocmdline in $robocmdTemp) {
            $roboArgs = $robocmdline
            debug 3 "   DEBUG :: roboargs is=$roboArgs (from previous instance missed robo cmd)" "Yellow" "log"
            debug 1 " PROCESS :: RoboCopy Mirror ...$roboArgs (from previous instance missed robo cmd)" "Cyan"
            Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), (from previous instance missed robo cmd) [RoboCopy mirror starting...] `n"
            $robologTempFile = "$PSScriptroot\$(Get-Random).robolog"
            #Start-Process ROBOCOPY.EXE -ArgumentList """$mediafolder$subfolder"" ""$remotePath$subfolder"" /MIR /XO /FFT /Z /MT:8 /R:4 /W:5" -Wait -NoNewWindow -RedirectStandardOutput $robologTempFile
            $rc = Start-Process -FilePath ROBOCOPY.EXE -ArgumentList $roboArgs -Wait -Passthru -NoNewWindow -RedirectStandardOutput $robologTempFile
            Do {} Until ($rc.HasExited) # wait...
            $robologTemp = Get-Content $robologTempFile
            ForEach ($roboline in $robologTemp) {
                Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), (from previous instance missed robo cmd) $roboline `n"
            }
            Remove-Item $robologTempFile -force
            $ExitMeaning = RoboCopyExitCodeMeaning($($rc.ExitCode))
            debug 3 "   DEBUG :: RoboCopy exitcode=$($rc.ExitCode) $ExitMeaning (from previous instance missed robo cmd)" "Yellow"
            Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), (from previous instance missed robo cmd) [RoboCopy mirror complete, exitcode=$($rc.ExitCode) $ExitMeaning] `n"
            $roboProcessTime = New-TimeSpan -Start $rc.StartTime
            debug 3 "   DEBUG :: This robocopy.exe process took $roboProcessTime seconds." "White" "log"
            Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "-------------------------"
            $roboCount++
        }    
        Remove-Item -Path $_.FullName -force
    }


### Create loop forever ######################################################
### use task scheduler to kill this script and start it again daily at 4:30am

    $startTime = (Get-Date)
    $currentTime = (Get-Date)
    $timeDiff = $currentTime-$startTime
    $global:roboWait = 0
    $roboerrorProcessAgainTimeout = 0
    
    While ($true) { # just loop until task scheduler kills the process and starts a new one (daily 4:30am)
           
        $currentTime = (Get-Date)
        $timeDiff = $currentTime-$startTime
        debug 1 "   CHECK :: Process events every ~$checkEverySeconds seconds, and perform RoboCopy mirrors every ~$($checkEverySeconds*$roboWaitCycle) seconds..." "Magenta"
        debug 1 "            (Events processed: $eventCount, Script runtime: $timeDiff)" "Green"
        
        debug 3 "   DEBUG :: roboWait is $global:roboWait (when $roboWaitCycle, set readyToROBO to True)" "Yellow"
        $readyToROBO = $false
        If ($global:roboWait -eq $roboWaitCycle) {
            $readyToROBO = $true
            $global:roboWait = 0
        }
        $global:roboWait++

        debug 3 "   DEBUG :: readyToROBO is $readyToROBO" "Yellow"
        If($global:roboCommands.Count -gt 0) {
            debug 3 "   DEBUG :: robocommands array is currently..." "Yellow"
            ForEach ($line in $global:roboCommands){
                debug 3 "            array line - $line" "Gray"
            }
        } Else {
            debug 3 "   DEBUG :: robocommands array is currently empty." "Yellow"
        }

        If ($readyToROBO -eq $true) {
            
            debug 1 "   CHECK :: Process RoboCopy entries every ~$($checkEverySeconds*$roboWaitCycle) seconds..." "Magenta"
            debug 1 "            (RoboCopy commands issued: $roboCount)" "Green"
            
            # only process if there are any robo commands
            If($global:roboCommands.Count -gt 0) {
                                
                write-host "**************************" -ForegroundColor Cyan
                debug 1 "ROBOCOPY :: $($global:roboCommands.Count) lines in roboCommands array to process..." "Cyan"
                debug 2 "    INFO :: Begin Robo'ing..." "Blue"

                $unknownRoboError = $false

                debug 3 "   DEBUG :: roboCommands array=$global:roboCommands`n" "" "log"

                $robologTempFile = "$PSScriptroot\$(Get-Random).robolog"

                # loop through roboCommands array and start ROBOCOPY mirror process for each line
                For ($i = 0; $i -lt $global:roboCommands.Count; $i++) {
                    $robologTempFile = "$PSScriptroot\$(Get-Random).robolog"
                    $roboArgs = $($global:roboCommands[$i][0])
                    debug 3 "   DEBUG :: processing array line $($i+1) of $($global:roboCommands.Count)" "Yellow" "log"
                    debug 3 "   DEBUG :: roboargs are=$roboArgs" "Yellow" "log"
                    debug 1 " PROCESS :: RoboCopy Mirror ...$roboArgs (attempt $($roboerrorProcessAgainTimeout+1))" "Cyan"
                    Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), RoboCopy mirror starting (attempt $($roboerrorProcessAgainTimeout+1))...`n"
                    #Start-Process ROBOCOPY.EXE -ArgumentList """$mediafolder$subfolder"" ""$remotePath$subfolder"" /MIR /XO /FFT /Z /MT:8 /R:4 /W:5" -Wait -NoNewWindow -RedirectStandardOutput $robologTempFile
                    $rc = Start-Process -FilePath ROBOCOPY.EXE -ArgumentList $roboArgs -Wait -Passthru -NoNewWindow -RedirectStandardOutput $robologTempFile
                    Do {} Until ($rc.HasExited) # wait...
                    $robologTemp = Get-Content $robologTempFile
                    ForEach ($roboline in $robologTemp) {
                        Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), $roboline `n"
                    }
                    Remove-Item $robologTempFile -force
                    $robocommandTempFile = $($global:roboCommands[$i][1])
                    Remove-Item $robocommandTempFile -force
                    $ExitMeaning = RoboCopyExitCodeMeaning($($rc.ExitCode))
                    debug 3 "   DEBUG :: RoboCopy exitcode=$($rc.ExitCode) $ExitMeaning" "Yellow"
                    Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "$(Get-Date -format 'dd-MMM-yyyy HH:mm:ss:fff'), [RoboCopy mirror complete, exitcode=$($rc.ExitCode) $ExitMeaning] `n"
                    $roboProcessTime = New-TimeSpan -Start $rc.StartTime
                    debug 3 "   DEBUG :: This robocopy.exe process took $roboProcessTime seconds." "White" "log"
                    Add-content "$LogPath$(Get-Date -UFormat '%Y-%m-%d').log" -Value "-------------------------"
                    $roboCount++
                    If ($($rc.ExitCode) -gt 16) {
                        $unknownRoboError = $true
                    }
                }
                debug 3 "   DEBUG :: looping through roboCommands array complete." "Yellow" "log"

                # only clear robocopy array and cmd files if unknownRoboError=$false, otherwise process again next time it loops
                # set roboerrorProcessAgainTimeout to 0 if robocopy exitcode meaningful otherwise increment until 5
                $roboerrorProcessAgainTimeout++
                debug 3 "   DEBUG :: unknownRoboError is currently ($unknownRoboError)" "Yellow" "log"
                debug 3 "   DEBUG :: roboerrorProcessAgainTimeout is currently $roboerrorProcessAgainTimeout" "Yellow" "log"
                If ( ($unknownRoboError -eq $false) -Or ($roboerrorProcessAgainTimeout -ge 5)) {
                    # all robo's done, reset roboerrorProcessAgainTimeout, reset readyToROBO to $false, clear roboCommands array and delete any .robocmd files
                    debug 3 "   DEBUG :: unknownRoboError($unknownRoboError)=False OR roboerrorProcessAgainTimeout ($roboerrorProcessAgainTimeout) is greater than or equal to 5" "Yellow" "log"
                    $unknownRoboError = $false
                    $roboerrorProcessAgainTimeout = 0
                    $readyToROBO = $false
                    $global:roboCommands = @()
                    #Remove-Item $PSSCriptroot\* -include *.robocmd -force
                    debug 3 "   DEBUG :: unknownRoboError reset to ($unknownRoboError)" "Yellow" "log"
                    debug 3 "   DEBUG :: readyToROBO reset to ($readyToROBO)" "Yellow" "log"
                    debug 3 "   DEBUG :: roboCommands array reset to ""$global:roboCommands""" "Yellow" "log"
                    #debug 3 "   DEBUG :: all .robocmd files removed" "Yellow" "log"
                    write-host "--------------------------" -ForegroundColor Cyan
                } else {
                    debug 3 "   DEBUG :: unknownRoboError($unknownRoboError)=True OR roboerrorProcessAgainTimeout ($roboerrorProcessAgainTimeout) is less than 5" "Yellow" "log"
                    debug 3 "   DEBUG :: so don't clear roboCommands array or delete .robocmd files as we want to try and process the mirror command again in the next loop (to a max of 5 attempts)" "Yellow" "log"
                    $unknownRoboError = $false
                    $readyToROBO = $false
                    debug 3 "   DEBUG :: unknownRoboError reset to ($unknownRoboError)" "Yellow" "log"
                    debug 3 "   DEBUG :: readyToROBO reset to ($readyToROBO)" "Yellow" "log"
                }

            } Else {
                debug 2 "    INFO :: roboCommands array is empty, nothing to mirror." "Blue"
            }
        }
        Start-Sleep $checkEverySeconds
    }#<--while loop forever 
###############################################################################
