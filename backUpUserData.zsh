#!/bin/zsh

# Sarah Keenan - October 5, 2020
# This script backs up all data under /Users/<current user>/ to an external hard drive

# Sarah Keenan - October 13, 2020
# Fixed permissions issue when copying.

# Sarah Keenan - October 16, 2020
# Moved DEPNotify section to after the popups. 
# Added function to wait for the computer to be plugged into AC power if it is not already. 

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

    set itemsToDelete to {"Finder", "Cisco AnyConnect Secure Mobility Client", "Self Service"}

    set cleanList to {}

    repeat with i from 1 to count runningApplicationsArray
        if {runningApplicationsArray's item i} is not in itemsToDelete then set cleanList's end to runningApplicationsArray's item i
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

# Create function to prompt for preferred network to remove
# Help from http://downloads.techbarrack.com/books/programming/AppleScript/website/lists/get_list_by_splitting_test.html
backupVolumePrompt () {
osascript <<EOF
    set theHDs to "$allExternalHDs"
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to ","
    set theHDsArray to every text item of theHDs
    set AppleScript's text item delimiters to oldDelimiters
    get theHDsArray
    set backupVolume to choose from list theHDsArray with prompt "Select the backup volume:"
EOF
}

# Erase external HD warning prompt
eraseWarningPrompt () {
osascript <<EOF
	set theIcon to POSIX file "/tmp/hardDriveIcon.png"
	set theMessage to "The following hard drive is about to be erased and reformatted: $backupVolume. Click \"I Understand and Erase\" if you are ready to erase this external hard drive."
	display dialog theMessage buttons {"Don't Erase", "I Understand and Erase"} default button "I Understand and Erase" with icon theIcon
EOF
}

waitForPower () {
	while [ "$powerConnected" = "No" ]; do
    	sleep 2
        powerConnected=$(system_profiler SPPowerDataType | grep "Connected:" | sed 's|Connected: ||g' | tr -d ' ')
    done
}

backUpManuallyPrompt () {
osascript <<EOF
	set theIcon to POSIX file "/tmp/hardDriveIcon.png"
    set theMessage to "Do you need to back up any data manually?"
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

# Get all external hard drives
externalHDs=$(ls /Volumes/ | grep -v "Macintosh HD" | sed 's/ /THIS_IS_A_SPACE/g')

declare -a externalHDsArray

for i in $externalHDs; do
	externalHDsArray+=( "$i" )
done

allExternalHDs=$(echo ${externalHDsArray[@]} | tr '\n' ',')
allExternalHDs=$(echo ${allExternalHDs%?} | sed 's/THIS_IS_A_SPACE/ /g')

# Prompt for backup volume
backupVolume=$(backupVolumePrompt)

echo "External HDs: $externalHDs"
echo "Backup Volume: $backupVolume"

if [[ -n "$backupVolume" ]] && [[ "$backupVolume" != "false" ]] && [[ -n "$externalHDs" ]]; then
    # Warn user about erasing the external HD
    eraseWarning=$(eraseWarningPrompt | sed "s|button returned:||g")
    echo $eraseWarning
fi

# ------------------------- Configure and Open DEPNotify -------------------------

# Set the log for DEPNotify
DEPNotifyLog="/var/tmp/depnotify.log"

# Set main DEPNotify Window
echo "Command: MainTitle: Backing Up Data for $currentUser." > ${DEPNotifyLog}
echo "Command: Image: $hardDriveIcon" >> ${DEPNotifyLog}
echo "Command: WindowStyle: ActivateOnStep" >> ${DEPNotifyLog}
echo "Command: WindowStyle: NotMovable" >> ${DEPNotifyLog}
echo "Command: MainText: We are backing up all of the data under /Users/$currentUser/. \n\n Make sure you manually back up any data at other locations, but do not put it in the Jamf_Backup folder on the hard drive." >> ${DEPNotifyLog}

# Open DEP Notify
open -a /Applications/Utilities/DEPNotify.app --args -fullScreen

# If there are no external HDs OR the prompt is cancelled, quit DEPNotify
if [[ -z "$externalHDs" ]] || [[ "$eraseWarning" == "Don't Erase" ]] || [[ "$backupVolume" == "false" ]]; then
	
	if [[ -z "$externalHDs" ]]; then
		error="No External Hard Drives Found"
		message="Could not find any external hard drives. Make sure you can see the hard drive in Finder or on your Desktop and try again."
	elif [[ "$eraseWarning" == "Don't Erase" ]]; then
    	error="Don't Erase External Hard Drive"
		message="You don't want to erase the external hard drive. Try again when you are ready to erase the external hard drive."
    elif [[ "$backupVolume" == "false" ]]; then
		error="Prompt Cancelled"
		message="You clicked cancel on the prompt. Make sure you can see the hard drive in Finder or on your Desktop."
    fi	
	
	echo "Command: WindowStyle: ActivateOnStep" >> ${DEPNotifyLog}
	echo "Status: ERROR: $error" >> ${DEPNotifyLog}
	echo "Command: Quit: $message" >> ${DEPNotifyLog}
	
	waitForDEPNotify
	
else

	# ------------------------------ AC Power Check ------------------------------
    echo "Status: Checking for power..."  >> ${DEPNotifyLog}
    
    powerConnected=$(system_profiler SPPowerDataType | grep "Connected:" | sed 's|Connected: ||g' | tr -d ' ')
    
    if [[ "$powerConnected" == "No" ]]; then
    	echo "Command: Alert: The MacBook must be connected to AC Power. Please connect a charger." >> ${DEPNotifyLog}
        waitForPower
    fi
    
    # ---------------------------- Erase External HD -----------------------------
    echo "Status: Erasing and reformatting $backupVolume..."  >> ${DEPNotifyLog}
    disk=$(diskutil list "$backupVolume" | awk '{ print $NF }' | grep "disk" | tr '\n' ' ' | awk '{ print $1 }')
    
    diskutil eraseDisk ExFAT "$backupVolume" /dev/$disk

	# -------------------------- Calculate Backup Size ---------------------------
	
	echo "Status: Calculating the size of the backup..."  >> ${DEPNotifyLog}

	# Get all user folders
	userFolderLocation="/Users/$currentUser/"
	
	totalUserFolderSize=$(du -d 0 -k /Users/$currentUser | awk '{ print $1 }')
	foldersToExclude=('Applications' 'Applications (Parallels)' 'Library' 'Parallels')
	amountToExclude=0
	
	for i in ${foldersToExclude[@]}; do
		exclude=$(du -d 0 -k /Users/$currentUser/"$i" | awk '{ print $1 }')
		amountToExclude=$(expr $amountToExclude + $exclude)
	done
	
	echo "The user's home folder size is $totalUserFolderSize"
	echo "The size of the folders to exclude is $amountToExclude"
	
	backupSize=$(expr $totalUserFolderSize - $amountToExclude)
	echo "The difference is $backupSize KB"
	
	# ------------------------ Calculate Free Space on HD ------------------------

	echo "Status: Calculating the free space on $backupVolume..."  >> ${DEPNotifyLog}

	# The free space on the external HD 
	freeSpaceHD=$(diskutil info /Volumes/$backupVolume | grep "Free Space:" | awk '{ print $6 }' | tr -d '(')
	echo "The free space on the external HD is $freeSpaceHD"

	# --------------------- Is there enough space on the HD? ---------------------

	echo "Status: Is there enough space on $backupVolume for the backup?"  >> ${DEPNotifyLog}

	# COMPARE
	difference=$(expr $freeSpaceHD - $backupSize)
	echo "The difference between the free space and the folder size is $difference KB."	

	if [[ $difference -lt 0 ]]; then 
		
		echo "Status: ERROR"  >> ${DEPNotifyLog}
		echo "Command: Quit: There is not enough free space on the backup volume, $backupVolume. Use another external hard drive with more space." >> ${DEPNotifyLog}

		waitForDEPNotify
		
	else
		echo "There is enough free space on the HD."
		
		# ---------------------- Get Installed Applications ----------------------
		
		echo "Status: Creating list of installed applications..."  >> ${DEPNotifyLog}
		
		computerName=$(scutil --get ComputerName)

		installedApplicationsList="/Users/$currentUser/installedApplications.txt"

		echo "This file contains a list of all the applications installed on $computerName." > ${installedApplicationsList}

		echo >> ${installedApplicationsList}

		echo "Remember to only install applications from Self Service or the Apple App Store." >> ${installedApplicationsList}
		echo "Do not install applications from the internet!" >> ${installedApplicationsList}

		echo >> ${installedApplicationsList}

		# Get Applications
		echo "The following applications were installed at /Applications/:" >> ${installedApplicationsList}
        for i in /Applications/*.app; do
        	echo $i | sed "s|/Applications/||g" >> ${installedApplicationsList}
        done

		echo >> ${installedApplicationsList}

		# Get User's Applications
		echo "The following applications were installed at /Users/$currentUser/Applications/:" >> ${installedApplicationsList}
        for i in /Users/$currentUser/Applications/*.app; do
        	echo $i | sed "s|/Users/$currentUser/Applications/||g" >> ${installedApplicationsList}
        done

		# -------------------- Get All User Folders and Files --------------------
		userFolderLocation="/Users/$currentUser/"
				
		numberOfFiles=0
		
		for item in $userFolderLocation*; do
			
			item=$(echo $item) # | sed -e "s|$userFolderLocation||g")
			
			if [[ -d "$item" ]]; then
                item=$(echo $item | sed -e "s|$userFolderLocation||g")
				echo "$item is a directory"
				allUserFoldersArray+=( "$item" )
			else
				item=$(echo $item | sed -e "s|$userFolderLocation||g")
				echo "$item is a file"
				let numberOfFiles++
				userFileArray+=( "$item" )
			fi

		
		done

		numberOfFolders=0

		for i in ${allUserFoldersArray[@]}; do
			if [[ "$i" == "Applications" || "$i" == "Applications (Parallels)" || "$i" == "Library" || "$i" == "Parallels" ]]; then
				echo "This folder, $i, should not be backed up"
			else
				let numberOfFolders++
				userFolderArray+=( "$i" )
			fi
		done
		
		
		for i in ${userFolderArray[@]}; do
			echo $i
		done
		
		echo "There are $numberOfFolders folders and $numberOfFiles files to back up"
		numberOfItems=$(expr $numberOfFolders + $numberOfFiles)

		# ------------------------------ Pre-Backup ------------------------------

		# Create backup folder
		today=$(date "+%m_%d_%Y")
		backupFolder="/Volumes/$backupVolume/Jamf_Backup_$today/" # Comment this line to test the script without external HD
	 	# backupFolder="/Users/Shared/Jamf_Backup_$today/" # Uncomment this line to test the script without an external HD
		mkdir $backupFolder
				
		# Set the number of folders to copy
		echo "Command: Determinate: $numberOfItems" >> ${DEPNotifyLog}
		
		# Set files to ignore in copy
		exclude="/tmp/exclude.txt"
		echo "desktop.ini" >> ${exclude}
		echo "\$RECYCLE.BIN" >> ${exclude}
		echo ".*" >> ${exclude}

		# ---------------------------- Backup Folders ----------------------------
		for ((i = 1; i <= ${#userFolderArray[@]}; i++)); do
			
			echo "Status: Copying ${userFolderArray[$i]}..." >> ${DEPNotifyLog}

			#mkdir "$backupFolder${userFolderArray[$i]}"

			echo "Copying ${userFolderArray[$i]}..."

			# Use rsync instead of cp to avoid copying desktop.ini, $RECYCLE.BIN, and other hidden files
            rsync -az --exclude-from="$exclude" "$userFolderLocation${userFolderArray[$i]}" "$backupFolder" #${userFolderArray[$i]}"

			echo "Copied ${userFolderArray[$i]}."

			echo "Fixing Permissions ${userFolderArray[$i]}..."
			
            permissions=$(ls -ld "$userFolderLocation${userFolderArray[$i]}")
			
			ownerPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c2-4 | tr -d '-')
			groupPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c5-7 | tr -d '-')
			otherPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c8-10 | tr -d '-')
						
			owner=$(echo $permissions | awk '{ print $3 }')
			group=$(echo $permissions | awk '{ print $4 }')
			
			echo "Permissions: $ownerPermissions $groupPermissions $otherPermissions"
			echo "Owner: $owner"
			echo "Group: $group"

			chown -R "$owner:$group" "$backupFolder${userFolderArray[$i]}"
			chmod u=$ownerPermissions,g=$groupPermissions,o=$otherPermissions "$backupFolder${userFolderArray[$i]}"

			echo "--"
		done
		        
		# ----------------------------- Backup Files -----------------------------
		for ((i = 1; i <= ${#userFileArray[@]}; i++)); do

			echo "Status: Copying ${userFileArray[$i]}..." >> ${DEPNotifyLog}
			            
			echo "Copying ${userFileArray[$i]}..."

			cp -R "$userFolderLocation${userFileArray[$i]}" "$backupFolder${userFileArray[$i]}"
            
			echo "Copied ${userFileArray[$i]}."

			echo "Fixing Permissions ${userFileArray[$i]}..."
			
			permissions=$(ls -ld "$userFolderLocation${userFileArray[$i]}")
			
			ownerPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c2-4 | tr -d '-')
			groupPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c5-7 | tr -d '-')
			otherPermissions=$(echo $permissions | awk '{ print $1 }' | cut -c8-10 | tr -d '-')
						
			owner=$(echo $permissions | awk '{ print $3 }')
			group=$(echo $permissions | awk '{ print $4 }')
			
			echo "Permissions: $ownerPermissions $groupPermissions $otherPermissions"
			echo "Owner: $owner"
			echo "Group: $group"

			chown -R "$owner:$group" "$backupFolder${userFileArray[$i]}"
			chmod u=$ownerPermissions,g=$groupPermissions,o=$otherPermissions "$backupFolder${userFileArray[$i]}"

			echo "--"
		done

        parallelsApplicationsFolder="Applications (Parallels)/"
        if [[ -e "$backupFolder$parallelsApplicationsFolder" ]]; then
        	echo "$backupFolder$parallelsApplicationsFolder exists"
        	rm -rf "$backupFolder$parallelsApplicationsFolder"
        fi


		# -------------------------------- Finish --------------------------------

		# Make sure everything is copied?
		
# 		homeFolderSize=$(expr $homeFolderSize + $fileSize)
# 		freeSpaceHD=$(diskutil info /Volumes/$backupVolume | grep "Free Space:" | awk '{ print $6 }' | tr -d '(')
# 
# 		freeSpaceHDAfter=$(diskutil info /Volumes/$backupVolume | grep "Free Space:" | awk '{ print $6 }' | tr -d '(')
# 
# 		before=$(expr $homeFolderSize + $freeSpaceHD)
# 
# 		difference=$(expr $before - $freeSpaceHDAfter)
# 		
# 		echo "(Home Folder Size + Free Space Before) - Free Space After = $difference"
		
		# Quit DEPNotify
		echo "Status: Done" >> ${DEPNotifyLog}
		/bin/echo "Command: Quit: Back up from /Users/$currentUser is complete. If you have data at other locations, remember to back it up manually into another folder." >> ${DEPNotifyLog}

		waitForDEPNotify

		
	fi
	
    # Ask the user if they need to back up any data manually
	backUpManually=$(backUpManuallyPrompt | sed 's|button returned:||g')
    
    echo $backUpManually
    
    if [[ "$backUpManually" == "No, I'm Done" ]]; then
    	diskutil eject /Volumes/"$backupVolume"
    elif [[ "$backUpManually" == "Yes" ]]; then
    	waitForUser
        diskutil eject /Volumes/"$backupVolume"
    fi
    
    wait 2
    HD_Ejected
    
fi