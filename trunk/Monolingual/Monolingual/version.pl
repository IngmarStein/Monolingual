#!/usr/bin/perl

if (defined($ARGV[0]) && defined($ARGV[1])) {
    open (IN, "curl -s --url \"$ARGV[0]\" | ") || die "\n";
    
    while ($hold = <IN>) {
	@tmp=split(/:/,$hold);
	if ($tmp[0] eq $ARGV[1]) {
            chomp($tmp[1]);
            print STDOUT $tmp[1];
        }
    }
#    print STDOUT "test";
    
    close(IN);
}

