#!/usr/bin/env perl
use bignum;
use warnings;
use strict;
use File::Compare;
use File::Copy;
use File::Temp;
use Sys::Hostname;

my $num_args = $#ARGV + 1;
if ($num_args < 2) {
    print "\nUsage: $0 <user> <shared directory> [mode (0 for active/passive or 1 for active/active)] [cron spool directory]\n";
    exit;
}

# We need a common directory for our nodes to write and read state from plus a couple of cronfiles
my ($user, $shareddir, $mode, $spooldir)  = @ARGV;

# Set some defaults if we didn't get them
unless ($mode == 0) {
	# mode 0 = active/passive, mode 1 = active/active
	print "Mode is active/active\n";
	$mode = 1;
} else {
	print "Mode is active/passive\n";

}
unless ($spooldir) { 
	$spooldir = "/var/spool/cron/crontabs";
}

my $sharedcrondir = "$shareddir/crontab";
my $cronfile = "$spooldir/$user";
my $activesharedcronfile = "$sharedcrondir/$user";
my $passivesharedcronfile = "$sharedcrondir/$user.passive";
my $oldactivesharedcronfile = "$sharedcrondir/$user.old";
my $oldpassivesharedcronfile = "$sharedcrondir/$user.passive.old";
my $electiondir = "$sharedcrondir/election";
my $hostname = hostname;
my $failovertimeout = 40;


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
		chomp $filename;
		my $nodename = $filename;
		$nodename =~ s/^$electiondir\///;
		# Don't add this host
		unless ($nodename eq $hostname) {
			my $node = {};
			open(FILE, "<$filename") or die "Could not open file: $!";
			$node->{'name'} = $nodename;
			my $content = <FILE>;
			chomp $content;
			$node->{'time'} = $content;
			$node->{'numeric'} = get_numeric($nodename);
			close FILE;
			push @nodes, $node;
		}
	}
	return @nodes;
	

}


# Simply write a unix timestamp to a file with our name on it
sub write_timestamp {
	my $time = time;
	open(FILE,"+>$electiondir/$hostname") or die "Could not open file: $!";
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
		#  If it has been active in the last 120 seconds it is eligable
		my $diff = time - $node->{'time'};
		if( $diff < $failovertimeout ) {
			print "Node: $node->{'name'} was active last $failovertimeout sec\n";
			# Go to passive mode if the numeric of that host is less than that of this host
			my $this = get_numeric($hostname);
			my $that = $node->{'numeric'};
			print "Numeric for $hostname is $this and for $node->{'name'} is $that\n";
			if( $this > $that ) {
				$state = 0 ;
				print "I am not active\n";
			} else {
				print "I am active\n";
				my $outfile = "$sharedcrondir/active";
				open(OUTFILE,"+>$outfile") or die "Could not open file: $!";
				print OUTFILE $hostname;
				close OUTFILE;
			}
		} else {
			print "Node: $node->{'name'} was not active last $failovertimeout sec\n";

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
		$line =~ s/(^(?!#))/# $1/g;
		$content .= $line;
	}
	
	close INFILE;
	open(OUTFILE,"+>$outfile") or die "Could not open file: $!";
	print OUTFILE $content;
	close OUTFILE;

}

# Remove a # from any crontab entry
sub uncomment {
        my ($infile, $outfile) = @_;
        open(INFILE,"<$infile");
        my $content = '';
        while(my $line = <INFILE>) {
                $line =~ s/^#\s{1,4}([\d\*])/ $1/g;
                $content .= $line;
        }

        close INFILE;
        open(OUTFILE,"+>$outfile") or die "Could not open file: $!";
        print OUTFILE $content;
        close OUTFILE;

}

sub cron_compare {
	my ($one, $two, $three) = @_;

	# Current cronfile and shared cronfile is not same
	if(compare($one, $two) != 0) {

		print "$one and $two is not the same\n";

		# This means that the other node has changed the cron file
		if(compare($one, $three) == 0) {

			print "Some other node has changed the file\n";
			return 1;
		# This means that my node has changed the cron file
		} else {

			print "This node has changed the cron file\n";
			return 2;
		}
	}

	return 0;

}

sub run {
	print "Host: $hostname started run at: " . time . "\n";
	print "Mode: $mode, user: $user, shareddir: $shareddir and spooldir: $spooldir\n";

	if(-e $activesharedcronfile) {
		unless(-e $oldactivesharedcronfile) {
			copy($activesharedcronfile, $oldactivesharedcronfile);
		}
	}

	unless (-d $electiondir) {
		mkdir $electiondir;
	}
	# If we are running in active/passive mode
	if($mode == 0) {
		if(-e $passivesharedcronfile) {
			unless(-e $oldpassivesharedcronfile) {
				copy($passivesharedcronfile, $oldpassivesharedcronfile);
			}
		}
		# Update timestamp
		write_timestamp;

		# If we have an active shared cronfile, we should also have an old shared
		# See if I am the one
		if (is_active(get_nodes) ){
			if(compare($cronfile, $passivesharedcronfile) == 0 ) {
				my $is_empty = 1;
				open my $fh, '<:encoding(UTF-8)', $activesharedcronfile or die;
				while (my $line = <$fh>) {
					if ($line !~ m/^#/) {
						$is_empty = 0;
					}
				}
				unless($is_empty) {
					print "There has been a failover, switching to active cronfile\n";
					copy($activesharedcronfile, $cronfile);
				}
			}
			my $tempfile = tmpnam();
			my $compare = cron_compare($cronfile, $activesharedcronfile, $oldactivesharedcronfile );
			# The other node has changed the file
			# This would mean that we are in some kind of multi master mode which is not invented yet, should not happen
			if($compare == 1) {
				copy($activesharedcronfile, $cronfile);
				copy($activesharedcronfile, $oldactivesharedcronfile);
			# This node has changed the file 
			} elsif ($compare == 2) {
				copy($cronfile, $activesharedcronfile);
				# Since we are the only master we need to update the old one as well
				copy($activesharedcronfile, $oldactivesharedcronfile);
				comment_out($cronfile, $passivesharedcronfile);
			}
			comment_out($cronfile, $tempfile);
			$compare = cron_compare($tempfile, $passivesharedcronfile, $oldpassivesharedcronfile);
			# The other node has changed the file
			if($compare == 1) {
				uncomment($passivesharedcronfile, $cronfile);
				copy($passivesharedcronfile, $oldpassivesharedcronfile);
				copy($cronfile, $activesharedcronfile);
				copy($activesharedcronfile, $oldactivesharedcronfile);
			# This node has changed the file 
			} elsif ($compare == 2) {
				copy($cronfile, $activesharedcronfile);
				comment_out($cronfile, $passivesharedcronfile);
			}
			unlink $tempfile;
		# We are passive node
		} else {
			my $compare = cron_compare($cronfile, $passivesharedcronfile, $oldpassivesharedcronfile );
			# The other node has changed the file
			if($compare == 1) {
				copy($passivesharedcronfile, $cronfile);
				copy($passivesharedcronfile, $oldpassivesharedcronfile);
			# We have changed stuff
			} elsif ($compare == 2) {
				comment_out($cronfile, $passivesharedcronfile);
				copy($passivesharedcronfile, $cronfile);
			}
		}
	}

	# If we are running in active/active mode
	else {
		my $compare = cron_compare($cronfile, $activesharedcronfile, $oldactivesharedcronfile );
		# The other node has changed the file
		if($compare == 1) {
			copy($activesharedcronfile, $cronfile);
			copy($activesharedcronfile, $oldactivesharedcronfile);
		# We have changed things
		} elsif ($compare == 2) {
			copy($cronfile, $activesharedcronfile);
		}
	}

	print "Host: $hostname finished run at: " . time . "\n\n\n";
}

for (my $i = 0; $i < 6; $i++) {
	my $start = time;
	$| = 1;
	run;
	if ((my $remaining = 10 - (time - $start)) > 0) {
		sleep $remaining;
	}
}

exit;

