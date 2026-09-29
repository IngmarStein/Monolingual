#!/bin/sh
# Create a read-only disk image of the contents of a folder
#
# Usage: make-diskimage <image_file>
#                       <src_folder>
#                       <volume_name>
#                       <codesign_identity>
#                       [applescript]
#                       [eula_resource_file]

set -e;

DMG_DIRNAME=$(dirname "$1")
DMG_DIR=$(cd "$DMG_DIRNAME" > /dev/null; pwd)
DMG_NAME=$(basename "$1")
DMG_TEMP_NAME=${DMG_DIR}/rw.${DMG_NAME}
SRC_FOLDER=$(cd "$2" > /dev/null; pwd)
VOLUME_NAME=$3
CODESIGN_IDENTITY=$4

# optional arguments
APPLESCRIPT=$5
EULA_RSRC=$6

# Create the image. Laying out the window below is done with the Finder, which needs a volume it
# can write to, so this one is created as a sparse, writable image and compressed below, once
# there is nothing left to write. Only APFS volumes are on offer here; the file system of the
# image is not something the app inside it can tell.
echo "creating disk image"
rm -f "$DMG_TEMP_NAME"
diskutil image create from "$SRC_FOLDER" "$DMG_TEMP_NAME" --format ASIF --volumeName "$VOLUME_NAME"

# mount it
echo "mounting disk image"
ATTACH_OUTPUT=$(diskutil image attach "$DMG_TEMP_NAME")
DEV_NAME=$(echo "$ATTACH_OUTPUT" | grep -E '^/dev/' | sed 1q | awk '{print $1}')
# The mount point comes from the attach output rather than from $VOLUME_NAME: a volume of that
# name may already be mounted, in which case this one is attached as "<name> 1" and a path built
# from $VOLUME_NAME would name — and then chmod — the volume that was already there. The first
# line naming a device is the whole disk and carries no mount point, so the line that has one is
# the one to read.
MOUNT_DIR=$(echo "$ATTACH_OUTPUT" | awk -F'\t' '$1 ~ /^\/dev\// && $3 != "" { print $3; exit }')
if [ -z "$MOUNT_DIR" ]; then
	echo "$DMG_TEMP_NAME was not mounted" >&2
	exit 1
fi

# run applescript
if [ -n "${APPLESCRIPT}" ] && [ "${APPLESCRIPT}" != "-null-" ]; then
	echo "running ${APPLESCRIPT}"
	/usr/bin/osascript "$APPLESCRIPT"
fi

# make sure it's not world writeable
echo "fixing permissions"
chmod -Rf go-w "${MOUNT_DIR}" || true

# make the top window open itself on mount:
if [ -x /usr/local/bin/openUp ]; then
	/usr/local/bin/openUp "${MOUNT_DIR}"
elif [ -x ~/bin/openUp ]; then
	~/bin/openUp "${MOUNT_DIR}"
fi

# unmount
echo "unmounting disk image"
diskutil eject "$DEV_NAME"

# compress image. Nothing writes to the image after this, so it goes out read-only, in the format
# that compresses best, which is lzma.
echo "compressing disk image"
rm -f "${DMG_DIR}/${DMG_NAME}"
diskutil image create from "$DMG_TEMP_NAME" "${DMG_DIR}/${DMG_NAME}" --format ULMO
rm -f "$DMG_TEMP_NAME"

# adding EULA resources. Unflattening is the one step here that hdiutil still has to do: the
# replacement has no equivalent for it.
if [ -n "${EULA_RSRC}" ] && [ "${EULA_RSRC}" != "-null-" ]; then
	echo "adding EULA resources"
	hdiutil unflatten "${DMG_DIR}/${DMG_NAME}"
	xcrun ResMerger -a "${EULA_RSRC}" -o "${DMG_DIR}/${DMG_NAME}"
	hdiutil flatten "${DMG_DIR}/${DMG_NAME}"
fi

# sign image
codesign -s "${CODESIGN_IDENTITY}" "${DMG_DIR}/${DMG_NAME}"

echo "disk image done"
exit 0
