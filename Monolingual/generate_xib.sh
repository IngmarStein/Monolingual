#!/bin/bash

primary=English
primarydir=$primary.lproj
for language in Japanese Swedish Polish German French Italian Spanish; do
	langdir=$language.lproj
	for f in `find $primary.lproj -name \*.xib -not -name \*~.xib -type f`; do
		xibfile=`basename $f`
		xibname=`basename $f .xib`
		stringsfile=$langdir/$xibname.strings
		if [ -e $stringsfile ]; then
			translated="$langdir/$xibfile"
			ibtool --import-strings-file $langdir/$xibname.strings $primarydir/$xibfile --write $translated
			echo Updated $langdir/$xibfile
		else
			cp $primarydir/$xibfile/*.xib $langdir/$xibfile
			echo $stringsfile not present, using English $xibfile
		fi
	done;
done
