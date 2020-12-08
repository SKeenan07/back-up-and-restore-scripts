#!/bin/zsh

# Sarah Keenan - October 13, 2020
# This script restores all data from a backup on an external HD.

# Sarah Keenan - October 20, 2020
# Added extra prompts and re-ordered the script to work with DEPNotify in full screen

# Get the current user
currentUser=$(stat -f%Su /dev/console)

# Download Hard Drive Icon
hardDriveIcon="/tmp/hardDriveIcon.png"
curl -s -o $hardDriveIcon https://cdn.pixabay.com/photo/2015/12/28/02/14/hard-drive-1110813_1280.png

# ------------------------------- Create Functions -------------------------------

# Get all applications that are running (except for Finder, AnyConnect, and Self Service)
# Help from https://macscripter.net/viewtopic.php?id=24525
# and https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/ManipulateListsofItems.html
getRunningApplications () {
osascript <<EOF
    on getPositionOfItemInList(theItem, theList)
        repeat with a from 1 to count of theList
            if item a of theList is theItem then return a
        end repeat
        return 0
    end getPositionOfItemInList

    on sortList(theList)
        set theIndexList to {}
        set theSortedList to {}
        repeat (length of theList) times
            set theLowItem to ""
            repeat with a from 1 to (length of theList)
                if a is not in theIndexList then
                    set theCurrentItem to item a of theList as text
                    if theLowItem is "" then
                        set theLowItem to theCurrentItem
                        set theLowItemIndex to a
                    else if theCurrentItem comes before theLowItem then
                        set theLowItem to theCurrentItem
                        set theLowItemIndex to a
                    end if
                end if
            end repeat
            set end of theSortedList to theLowItem
            set end of theIndexList to theLowItemIndex
        end repeat
        return theSortedList
    end sortList

    tell application "System Events"
        get name of (processes where background only is false)
    end tell

    set runningApplications to result

    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to ","
    set runningApplicationsArray to every text item of runningApplications
    set AppleScript's text item delimiters to oldDelimiters
    get runningApplicationsArray

    set applicationsToNotClose to {"Finder", "Cisco AnyConnect Secure Mobility Client", "Self Service"}

    set cleanList to {}

    repeat with i from 1 to count runningApplicationsArray
        if {runningApplicationsArray's item i} is not in applicationsToNotClose then set cleanList's end to runningApplicationsArray's item i
    end repeat

    sortList(cleanList)
EOF
}

# Close open applications prompt
closeApps () {
osascript <<EOF
	set theIcon to POSIX file "/tmp/hardDriveIcon.png"
	set theMessage to "Please close the following applications: \n$runningApplications \nClick OK when finished."
	display dialog theMessage buttons {"OK"} default button "OK" with icon theIcon
EOF
}

# Create function to prompt for the backup folder
backupFolderPrompt () {
osascript <<EOF
	set defaultFolder to POSIX file "/Volumes/"
	set theOutputFolder to choose folder with prompt "Please select the Jamf_Backup folder: " default location defaultFolder
EOF
}

restorePrompt () {
osascript <<EOF
	set theIcon to POSIX file "/tmp/hardDriveIcon.png"
	set theFolder to "$backupFolder"
	set theMessage to "You are about to restore data from the following folder: $backupFolder. This restore process only works properly on a machine without any data. If you have started to use this machine and created or copied files, then this process may erase or overwrite those files. Click \"I Understand and Restore\" if you understand and are ready to restore your data. If you already have data on this machine, contact IT to restore your data manually."

	display dialog theMessage buttons {"Don't Restore", "I Understand and Restore"} default button "I Understand and Restore" with icon theIcon
EOF
}

waitForPower () {
	while [ "$powerConnected" = "No" ]; do
    	sleep 2
        powerConnected=$(system_profiler SPPowerDataType | grep "Connected:" | sed 's|Connected: ||g' | tr -d ' ')
    done
}

restoreManuallyPrompt () {
osascript <<EOF
	set theIcon to POSIX file "/tmp/hardDriveIcon.png"
    set theMessage to "Do you need to restore any data manually?"
    display dialog theMessage buttons {"Yes", "No, I'm Done"} default button "No, I'm Done" with icon theIcon
EOF
}

HD_Ejected () {
osascript <<EOF
	set theIcon to POSIX file "/tmp/hardDriveIcon.png"
	set theMessage to "The external hard drive was safely ejected. You may now remove the external hard drive from your computer."
	display dialog theMessage buttons {"OK"} default button "OK" with icon theIcon
EOF
}

waitForUser () {
osascript <<EOF
	set theIcon to POSIX file "/tmp/hardDriveIcon.png"
    set theMessage to "Leave this window open while you copy the rest of your data. When you are finished, click OK."
    display dialog theMessage buttons {"OK"} default button "OK" with icon theIcon
EOF
}

# Create function to wait for DEPNotify to quit
waitForDEPNotify () {
	# Get the PID for the DEPNotify Process
	DEPNotifyProcess=$(ps -axc | grep "DEPNotify" | awk '{ print $1 }')

	# Keeps DEPNotify open until the user acknowledges the "Finished" message
	if [[ -n $DEPNotifyProcess ]]; then
		while kill -0 "$DEPNotifyProcess" 2> /dev/null; do
			sleep 1
		done
	fi
}

# ----------------------------- Prerequisite Prompts -----------------------------

# Get open applications
runningApplications=$(getRunningApplications)

# While there are other applications open, prompt the user
while [ -n "$runningApplications" ]; do
	closeApps
	runningApplications=$(getRunningApplications)
done

# backupFolder=$(backupFolderPrompt | sed -a 's/alias //g' | tr ':' '/')
backupFolderAlias=$(backupFolderPrompt | sed 's/alias //g' | tr ':' '/')
echo $backupFolderAlias

backupFolder="/Volumes/$backupFolderAlias"
echo $backupFolder

restore=$(restorePrompt | sed "s|button returned:||g")


# ------------------------- Configure and Open DEPNotify -------------------------

# Set the log for DEPNotify
DEPNotifyLog="/var/tmp/depnotify.log"

# Set main DEPNotify Window
echo "Command: MainTitle: Restoring Data for $currentUser." > ${DEPNotifyLog}
echo "Command: Image: $hardDriveIcon" >> ${DEPNotifyLog}
echo "Command: WindowStyle: ActivateOnStep" >> ${DEPNotifyLog}
echo "Command: WindowStyle: NotMovable" >> ${DEPNotifyLog}
echo "Command: MainText: We are restoring all of the data from the backup. \n\n Remember to restore any additional data if applicable. \n\n Also, remember to install any additional approved applications in the installed applications file. This file will open at the end of the restore process." >> ${DEPNotifyLog}

# Open DEP Notify
open -a /Applications/Utilities/DEPNotify.app --args -fullScreen

# If the prompt was cancelled, quit DEPNotify
if [[ -z "$backupFolderAlias" ]] || [[ "$restore" == "Don't Restore" ]] || [[ "$backupFolderAlias" != *"Jamf_Backup_"* ]]; then

	if [[ -z "$backupFolderAlias" ]]; then
		error="Prompt Cancelled"
		message="You canceled the prompt. Make sure you can see the external hard drive in Finder or on your Desktop. Try again."
	elif [[ "$restore" == "Don't Restore" ]]; then
    	error="Don't Restore"
        message="You don't want to restore your data. Try again when you are ready to restore your data."
    elif [[ "$backupFolderAlias" != *"Jamf_Backup_"* ]]; then
		error="Wrong Folder Selected"
		message="The folder name must contain \"Jamf_Backup_\". You can only use this program if you used Self Service to back up your data."
	fi
	
	echo "Command: WindowStyle: ActivateOnStep" >> ${DEPNotifyLog}
	echo "Status: ERROR: $error" >> ${DEPNotifyLog}
	echo "Command: Quit: $message" >> ${DEPNotifyLog}
	
	waitForDEPNotify
else
	
	userHomeFolder="/Users/$currentUser/" # Comment this line to test
	#userHomeFolder="/Users/$currentUser/Desktop/test_restore/" # Uncomment this line to test
	
	# ------------------------------ AC Power Check ------------------------------
    echo "Status: Checking for power..."  >> ${DEPNotifyLog}
    
    powerConnected=$(system_profiler SPPowerDataType | grep "Connected:" | sed 's|Connected: ||g' | tr -d ' ')
    
    if [[ "$powerConnected" == "No" ]]; then
    	echo "Command: Alert: The MacBook must be connected to AC Power. Please connect a charger." >> ${DEPNotifyLog}
        waitForPower
    fi

	# ------------------------------ Get All Items -------------------------------

	echo "Status: Looking for items to copy..." >> ${DEPNotifyLog}
	
	declare -a foldersToRestore
	declare -a filesToRestore
	
	for i in "$backupFolder"*; do
		if [[ -d $i ]]; then
			i=$(echo $i | sed "s|$backupFolder||g")
			foldersToRestore+=( "$i" )
		else
			i=$(echo $i | sed "s|$backupFolder||g")
			filesToRestore+=( "$i" )
		fi
	done
	
	echo "Folders"
	for i in ${foldersToRestore[@]}; do
		echo $i
	done
	
	echo
	
	echo "Files"
	for i in ${filesToRestore[@]}; do
		echo $i
	done
	
	echo 
	
	numberOfItems=$(expr ${#foldersToRestore[@]} + ${#filesToRestore[@]})
	
	echo "Status: Copying Folders..." >> ${DEPNotifyLog}

	echo "Command: Determinate: $numberOfItems" >> ${DEPNotifyLog}
	
	# --------------------------------- Restore ----------------------------------

	owner="$currentUser"
	group="staff"

	for ((i = 1; i <= ${#foldersToRestore[@]}; i++)); do	
	
		echo "Status: Copying ${foldersToRestore[$i]}..." >> ${DEPNotifyLog}
		
		# If the folder does not exist in the user's home folder, remove the / at the end 
		# of the folder so the script will backup the whole folder.
		# cp -R /source/folder /destination/ will copy the whole folder
		# cp -R /source/folder/ /destination/ will copy the contents of the folder
		
		# If exists, get permissions
		# If not, remove the / and set the permissions to the source permissions
		
		if [[ -e $userHomeFolder${foldersToRestore[$i]} ]]; then
			folder="${foldersToRestore[$i]}/"
			
			permissions=$(ls -ld "$userHomeFolder${foldersToRestore[$i]}")
		else
			folder="${foldersToRestore[$i]}"
			
			permissions=$(ls -ld "$backupFolder${foldersToRestore[$i]}")
		fi

		ownerPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c2-4 | tr -d '-')
		groupPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c5-7 | tr -d '-')
		otherPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c8-10 | tr -d '-')
							
		echo $folder
		echo "Permissions: $ownerPermissions $groupPermissions $otherPermissions"

		echo --
		
		cp -pR "$backupFolder$folder" "$userHomeFolder$folder"
		
		chown -R "$owner:$group" "$userHomeFolder$folder"
		chmod u=$ownerPermissions,g=$groupPermissions,o=$otherPermissions "$userHomeFolder$folder"

	done
	
	
	for ((i = 1; i <= ${#filesToRestore[@]}; i++)); do	
	
		echo "Status: Copying ${filesToRestore[$i]}..." >> ${DEPNotifyLog}

		permissions=$(ls -ld "$backupFolder${filesToRestore[$i]}")
	
		ownerPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c2-4 | tr -d '-')
		groupPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c5-7 | tr -d '-')
		otherPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c8-10 | tr -d '-')
		
		echo ${filesToRestore[$i]}
		echo "Permissions: $ownerPermissions $groupPermissions $otherPermissions"
		
		echo --
		
		cp -pR "$backupFolder${filesToRestore[$i]}" "$userHomeFolder${filesToRestore[$i]}"
		
		chown -R "$owner:$group" "$userHomeFolder${filesToRestore[$i]}"
		chmod u=$ownerPermissions,g=$groupPermissions,o=$otherPermissions "$userHomeFolder${filesToRestore[$i]}"

	done
	
	# Quit DEPNotify
	echo "Status: Done" >> ${DEPNotifyLog}
	echo "Command: Quit: All data has been restored. See /Users/$currentUser/installedApplications.txt for a list of applications previously installed." >> ${DEPNotifyLog}

	waitForDEPNotify
    
    # Ask the user if they need to back up any data manually
	restoreManually=$(restoreManuallyPrompt | sed 's|button returned:||g')
    
    echo $restoreManually
    
    backupVolume=$(echo $backupFolder | sed 's| |THIS_IS_A_SPACE|g' | tr '/' ' ' | awk '{ print $2 }' | sed 's|THIS_IS_A_SPACE| |g')
    echo $backupVolume
    
    if [[ "$restoreManually" == "No, I'm Done" ]]; then
    	diskutil eject /Volumes/"$backupVolume"
    elif [[ "$restoreManually" == "Yes" ]]; then
    	waitForUser
        diskutil eject /Volumes/"$backupVolume"
    fi
    
    wait 2
    HD_Ejected

fi