#!/bin/bash

primary=English
primarydir=$primary.lproj
for language in Japanese Swedish Polish German French Italian; do
	langdir=$language.lproj
	for f in `find $primary.lproj -name \*.nib -not -name \*~.nib -type d`; do
		nibfile=`basename $f`
		nibname=`basename $f .nib`
		stringsfile=$langdir/$nibname.strings
		mkdir -p $langdir/$nibfile
		if [ -e $stringsfile ]; then
			translated="$langdir/$nibname-new.nib"
			nibtool -d $langdir/$nibname.strings $primarydir/$nibfile -W $translated
			cp $translated/*.nib $langdir/$nibfile
			rm -rf $translated $langdir/*~.nib
			touch $langdir/$nibfile
			echo Updated $langdir/$nibfile
		else
			cp $primarydir/$nibfile/*.nib $langdir/$nibfile
			echo $stringsfile not present, using English $nibfile
		fi
	done;
done
