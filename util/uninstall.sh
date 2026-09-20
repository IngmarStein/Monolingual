#!/bin/sh
# Removes a privileged helper that Monolingual 1.9.0 and earlier installed with SMJobBless.
# Helpers registered by newer versions live inside the app bundle and are removed by
# unregistering them in System Settings › General › Login Items & Extensions.
sudo launchctl bootout system/com.github.IngmarStein.Monolingual.Helper
sudo rm -f /Library/LaunchDaemons/com.github.IngmarStein.Monolingual.Helper.plist
sudo rm -f /Library/PrivilegedHelperTools/com.github.IngmarStein.Monolingual.Helper
