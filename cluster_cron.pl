#!/usr/bin/env perl
use warnings;
use strict;
use Sys::Hostname;
use File::Compare;
use File::Copy;

# We need a common directory for our nodes to write and read state from plus a couple of cronfiles
my ($mode, $user, $shareddir, $spooldir) = @_;

# Set some defaults if we didn't get them
unless ($mode) {
	# mode 0 = active/passive, mode 1 = active/active
	$mode = 1;
}
unless ($user) {
	$user = "www-data";
}
unless ($shareddir) {
	$shareddir = "/var/lib/thruk";
}
unless ($spooldir) { 
	$spooldir = "/var/spool/cron/crontabs";
}

my $sharedcrondir = "$shareddir/crontab";
my $cronfile = "$spooldir/$user";
my $sharedcronfile = "$sharedcrondir/$user";
my $oldsharedcronfile = "$sharedcrondir/$user.old";
my $electiondir = "$sharedcrondir/election";
my $hostname = hostname;
my $time = time;

# Create directories 
unless (-d $sharedcrondir) {
	mkdir $sharedcrondir or die "Can not create shared directory: $!";
}



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

# If we are running in active/active mode
if($mode) {
	unless (-d $electiondir) {
		mkdir $electiondir;
	}

	# Update timestamp
	write_timestamp;

	# See if I am the one
	if (is_active(get_nodes) ){
		uncomment $sharedcronfile, $cronfile;

	} else {
		comment_out $cronfile, $sharedcronfile;
	}

}

# If we are running in actie/passive mode
else {
	# If we don't have any cronjob on this host
	unless (-e $cronfile) {
		# If we have a cronjob on the shared drive
		if (-e $sharedcronfile) {
			copy($sharedcronfile, $cronfile) or die "Copy failed: $!";
			copy($sharedcronfile, $oldsharedcronfile) or die "Copy failed: $!";
		} 
		# Nothing to do, no cronjob on any host
		exit;
	} 

	# If there is no cronjob on the shared drive
	unless (-e $sharedcronfile) {
		# But we have a cronjob on this host
		if (-e $cronfile) {
			copy($cronfile, $sharedcronfile) or die "Copy failed: $!";

		}
		exit;
	} 

	# Current cronfile and shared cronfile is not same
	if(compare($cronfile, $sharedcronfile) != 0) {

		# This means that the other node has changed the cron file
		if(compare($cronfile, $oldsharedcronfile) == 0) {
			copy($sharedcronfile, $cronfile) or die "Copy failed: $!";
			copy($sharedcronfile, $oldsharedcronfile) or die "Copy failed: $!";
			# All files are now the same
		# This means that my node has changed the cron file
		} else {
			copy($cronfile, $sharedcronfile) or die "Copy failed: $!";
			# The other node will now detect the difference and do the correct adjustment
		}
	}


}

exit;
