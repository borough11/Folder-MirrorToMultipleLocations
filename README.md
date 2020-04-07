# Folder-MirrorToMultipleLocations

# Synopsis

Monitor master folder (including subfolders) and sync any changes to multiple remote shares using RoboCopy.

# Description

Sets up a FileSystemWatcher on "mediafolder" that monitors this directory and all subdirectories for the created/changed/renamed/deleted file events only (not directory events).
This happens every x amount of seconds (can be set in variables below). When an event is noticed, it is processed and if OK a respective RoboCopy command is added to an array. (this is because if 100 files are copied in we don't want to run a RoboCopy mirror 100 times on the same folder unnecessarily).
Every x cycles of the event monitoring loop (can be set in variables below), this array is checked and if there are any rows, they are executed as RoboCopy commands. This mirrors the "mediafolder" to all remote folders and writes to the log file.

# Example log output
```
DEBUG (2):    DEBUG :: this is a FILE event (folder\file.jpg) [event id=1]
DEBUG (2):    DEBUG :: changetype matches, process it, (Created)
-------------------------
07-Apr-2020 07:37:14:288, FileSystemWatcher update noticed...
07-Apr-2020 07:37:14:288,  [event count = 1]
07-Apr-2020 07:37:14:288,  [event = Created @ 07:36:59:545]
07-Apr-2020 07:37:14:288,  [fullpath = (D:\media\folder\file.jpg)]
07-Apr-2020 07:37:14:288,  [fullfolderpath = (D:\media\folder)]
07-Apr-2020 07:37:14:288,  [subfolder = (\folder)]
07-Apr-2020 07:37:14:288,  [folder exists = True]
07-Apr-2020 07:37:14:288,  [add arguments to roboCommands array for RoboCopy mirroring...]
07-Apr-2020 07:37:14:288,  [args = adding line to roboCommands array - "D:\media\folder" "\\server02\media\folder" /MIR /XO /FFT /Z /MT /XX /R:4 /W:2]
07-Apr-2020 07:37:14:335,  [args = adding line to roboCommands array - "D:\media\folder" "\\server03\media\folder" /MIR /XO /FFT /Z /MT /XX /R:4 /W:2]
-------------------------
DEBUG (2):    DEBUG :: processing array line 1 of 2
DEBUG (2):    DEBUG :: roboargs are= "D:\media\folder" "\\server02\media\folder" /MIR /XO /FFT /Z /MT /XX /R:4 /W:2
07-Apr-2020 07:38:14:410, RoboCopy mirror starting (attempt 1)...
07-Apr-2020 07:38:15:566, ------------------------------------------------------------------------------- 
07-Apr-2020 07:38:15:566,    ROBOCOPY     ::     Robust File Copy for Windows                               
07-Apr-2020 07:38:15:566, ------------------------------------------------------------------------------- 
07-Apr-2020 07:38:15:566,   Started : Tuesday, 7 April 2020 7:38:14 a.m. 
07-Apr-2020 07:38:15:566,    Source : D:\media\folder\ 
07-Apr-2020 07:38:15:566,      Dest : \\server02\media\folder\ 
07-Apr-2020 07:38:15:566,     Files : *.* 
07-Apr-2020 07:38:15:566,   Options : *.* /FFT /S /E /DCOPY:DA /COPY:DAT /PURGE /MIR /Z /XX /XO /MT:8 /R:4 /W:2  
07-Apr-2020 07:38:15:581, ------------------------------------------------------------------------------ 
07-Apr-2020 07:38:15:581, 	    New File  		   76092	D:\media\folder\file.jpg 
07-Apr-2020 07:38:15:581, ------------------------------------------------------------------------------ 
07-Apr-2020 07:38:15:581,    Ended : Tuesday, 7 April 2020 7:38:15 a.m. 
07-Apr-2020 07:38:15:675, [RoboCopy mirror complete, exitcode=1 OKCOPY] 
DEBUG (2):    DEBUG :: This robocopy.exe process took 00:00:01.1872769 seconds.
-------------------------
DEBUG (2):    DEBUG :: processing array line 2 of 2
DEBUG (2):    DEBUG :: roboargs are= "D:\media\folder" "\\server03\media\folder" /MIR /XO /FFT /Z /MT /XX /R:4 /W:2
07-Apr-2020 07:38:15:691, RoboCopy mirror starting (attempt 1)...
07-Apr-2020 07:38:16:699, ------------------------------------------------------------------------------- 
07-Apr-2020 07:38:16:699,    ROBOCOPY     ::     Robust File Copy for Windows                               
07-Apr-2020 07:38:16:699, ------------------------------------------------------------------------------- 
07-Apr-2020 07:38:16:699,   Started : Tuesday, 7 April 2020 7:38:15 a.m. 
07-Apr-2020 07:38:16:699,    Source : D:\media\folder\ 
07-Apr-2020 07:38:16:715,      Dest : \\server03\media\folder\ 
07-Apr-2020 07:38:16:731,     Files : *.* 
07-Apr-2020 07:38:16:731,   Options : *.* /FFT /S /E /DCOPY:DA /COPY:DAT /PURGE /MIR /Z /XX /XO /MT:8 /R:4 /W:2  
07-Apr-2020 07:38:16:731, ------------------------------------------------------------------------------ 
07-Apr-2020 07:38:16:746, 	    New File  		   76092	D:\media\folder\file.jpg 
07-Apr-2020 07:38:16:746, ------------------------------------------------------------------------------ 
07-Apr-2020 07:38:16:746,    Ended : Tuesday, 7 April 2020 7:38:16 a.m. 
07-Apr-2020 07:38:16:746, [RoboCopy mirror complete, exitcode=1 OKCOPY] 
DEBUG (2):    DEBUG :: This robocopy.exe process took 00:00:01.0554310 seconds.
-------------------------
DEBUG (2):    DEBUG :: looping through roboCommands array complete.
DEBUG (2):    DEBUG :: unknownRoboError is currently (False)
DEBUG (2):    DEBUG :: roboerrorProcessAgainTimeout is currently 1
DEBUG (2):    DEBUG :: unknownRoboError(False)=False OR roboerrorProcessAgainTimeout (1) is greater than or equal to 5
DEBUG (2):    DEBUG :: unknownRoboError reset to (False)
DEBUG (2):    DEBUG :: readyToROBO reset to (False)
DEBUG (2):    DEBUG :: roboCommands array reset to ""
-------------------------
```

# Blah
Need to come back and detail this at a future date
