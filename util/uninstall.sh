#!/bin/sh
#sudo launchctl unload /Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist
sudo rm /Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist
sudo rm /Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper
sudo launchctl stop com.github.IngmarStein.Monolingual.Helper
sudo launchctl remove com.github.IngmarStein.Monolingual.Helper
