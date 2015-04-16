#!/bin/sh
#sudo launchctl unload /Library/LaunchDaemons/net.sourceforge.MonolingualHelper.plist
sudo rm /Library/LaunchDaemons/net.sourceforge.MonolingualHelper.plist
sudo rm /Library/PrivilegedHelperTools/net.sourceforge.MonolingualHelper
sudo launchctl stop net.sourceforge.MonolingualHelper
sudo launchctl remove net.sourceforge.MonolingualHelper
