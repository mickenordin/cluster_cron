#!/usr/bin/env perl
use warnings;
use strict;
use Sys::Hostname;

# We need a common directory for our nodes to write and read state from plus a couple of cronfiles
my ($electiondir, $cronfile, $sharedcronfile) = @_;

unless (-d $electiondir) {
        mkdir $electiondir;
}

# We need our name
my $hostname = hostname;

# We also need to know the time
my $time = time;


# Get the nodes in the cluster
sub get_nodes {
        # Our data type is a hash with the following fields
        # name, time, numeric
        my @nodes = ();
        my @files = <$electiondir/*>;
        foreach my $filename (@files) {
                my $node = {};
                open(FILE, "<$filename") or die "Could not open file: $!";
                $filename =~ s/^$electiondir\///;
                $node->{'name'} = $filename;
                my $content = <FILE>;
                chomp $content;
                $node->{'time'} = $content;
                $node->{'numeric'} = get_numeric($filename);
                close FILE;
                push @nodes, $node;
        }
        return @nodes;


}


# Simply write a unix timestamp to a file with our name on it
sub write_timestamp {
        open(FILE,"+>$electiondir/$hostname");
        print FILE $time;
        close FILE;

}

# Lets see if we are the active node
sub is_active {

        my @nodes = @_;

        # Assume you are active
        my $state = 1;
        # Loop all nodes
        foreach my $node (@nodes) {
                # Dont do anything if this is the node
                unless ($node eq $node->{'name'}) {
                        #  If it has been active in the last 120 seconds it is eligable
                        my $diff = $time - $node->{'time'};
                        if( $diff < 120 ) {
                                # Go to passive mode if the numeric of that host is less than that of this host
                                if( get_numeric($hostname) > $node->{'numeric'} ) {
                                        $state = 0 ;
                                }
                        }
                }
        }
        return $state;
}

# Turn a hostname in to a decimal number used for comparison, lowest numer gets to be active if it is working
sub get_numeric {
        my ($host) = @_;
        my @ascii = unpack 'C*', $host;
        my $numeric = '';
        foreach my $val (@ascii) {
                $numeric .=  $val;
        }
        return $numeric + 0;
}

# But a # infront of any actime crontab entry 
sub comment_out {
        my ($infile, $outfile) = @_;
        open(INFILE,"<$infile");
        my $content = '';
        while(my $line = <INFILE>) {
                $line =~ s/(^(?!#))/#$1/g;
                $content .= $line;
        }

        close INFILE;
        open(OUTFILE,"+>$outfile");
        print OUTFILE $content;
        close OUTFILE;

}

# Remove a # from any crontab entry
sub uncomment {
        my ($infile, $outfile) = @_;
        open(INFILE,"<$infile");
        my $content = '';
        while(my $line = <INFILE>) {
                $line =~ s/^(#)([\d*])/$2/g;
                $content .= $line;
        }

        close INFILE;
        open(OUTFILE,"+>$outfile");
        print OUTFILE $content;
        close OUTFILE;

}

# Update timestamp
write_timestamp;

# See if I am the one
if (is_active(get_nodes) ){
        uncomment $sharedcronfile, $cronfile;

} else {
        comment_out $cronfile, $sharedcronfile;
}
