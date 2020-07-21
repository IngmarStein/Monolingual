#!/bin/bash
cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
EOF
find /Applications/Adobe* -name Info.plist -print0 | while read -r -d $'\0' file; do
	bundleid=$(/usr/libexec/PlistBuddy -c Print:CFBundleIdentifier "$file" 2>&1)
	rc=$?
	if [[ $rc == 0 ]]; then
		echo "<dict><key>architectures</key><true/><key>bundle</key><string>$bundleid</string><key>languages</key><true/></dict>"
	fi
done
cat <<EOF
</array>
</plist>
EOF
