#!/usr/bin/perl -w

#######################################################################
# monolingual.pl -
#   strips away extra language .lproj from OSX to save space
#
#    Copyright (C) 02001  Joshua Schrier (jschrier@mac.com)
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#######################################################################

my @lang_name = ('Chinese','Finnish','Korean','Danish','French','Norwegian','Dutch','German','Portuguese', 
            'English','Italian','Spanish','Pig-latin','Japanese','Swedish','Australian','British');
my @lang_code = ('zh','fi','ko','da','fr','no','nl','de','pt','en','it','es','xx','ja','sv','en_AU','en_GB');
# my @lang_code_en = ('en_AU','en_GB');
my @lang_code_zh = ('zh_CN','zh_TW');
my $paths = "/Applications /System /Library";

# my @offset = (666,-12,-13,-13,-13,-14,-15,-14);

if (!(defined($ARGV[0]))) {
    print STDOUT "\nmonolingual 1.2.0, Copyright (C) 2002 J. Schrier, 2004 Ingmar Stein\n";
    print STDOUT "\nmonolingual comes with ABSOLUTELY NO WARRANTY; for details refer to\n";
    print STDOUT "the included documentation (readme.txt) or the script itself (monolingual.pl\n";
    print STDOUT "This is free software, and you are welcome to redistribute it\n";
    print STDOUT "under the terms of the GNU Public License (gpl.txt)\n";

    print STDOUT "\nLanguage to remove:\n";
    for my $i (0..16) {
		print STDOUT "$i) $lang_name[$i]\n";
    }
    print STDOUT "Enter your selection: ";
    chop($lang = <STDIN>);
    
    print STDOUT "Are you *SURE* you want to *REMOVE ALL* $lang_name[$lang] ";
    print STDOUT "resources from OS X?\n";
    print STDOUT "You will *NOT* be able to restore them without reinstalling OS X.\n";
    print STDOUT "(Type \'yes\' to REMOVE $lang_name[$lang])  ";

    chop($agree = <STDIN>);
    ($agree eq "yes") || die "Your files have *NOT* been changed.\n";
	push(@remove, $lang);
} else {
	foreach my $lang (@ARGV) {
		if($lang == 0) {
			for my $i (0..1) {
				push(@remove, $lang_code_zh[$i].".lproj");
			}
		} else {
			push(@remove, $lang_name[$lang].".lproj");
			push(@remove, $lang_code[$lang].".lproj");
		}
	}
}

my $names = join(" -or -name ", @remove);

system("find $paths -type d \\( -name $names \\) -print0 | xargs -0 rm -r");

