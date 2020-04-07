# Folder-MirrorToMultipleLocations

# Synopsis

Monitor master folder (including subfolders) and sync any changes to multiple remote shares using RoboCopy.

# Description

Sets up a FileSystemWatcher on "mediafolder" that monitors this directory and all subdirectories for the created/changed/renamed/deleted file events only (not directory events).
This happens every x amount of seconds (can be set in variables below). When an event is noticed, it is processed and if OK a respective RoboCopy command is added to an array. (this is because if 100 files are copied in we don't want to run a RoboCopy mirror 100 times on the same folder unnecessarily).
Every x cycles of the event monitoring loop (can be set in variables below), this array is checked and if there are any rows, they are executed as RoboCopy commands. This mirrors the "mediafolder" to all remote folders and writes to the log file.
                   
# Blah
Need to come back and detail this at a future date
