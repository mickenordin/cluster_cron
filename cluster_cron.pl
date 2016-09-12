#!/usr/bin/env perl
use warnings;
use strict;
use bignum;
use Sys::Hostname;
use File::Compare;
use File::Copy;

# We need a common directory for our nodes to write and read state from plus a couple of cronfiles
my $mode = $ARGV[0];
my $user = $ARGV[1];
my $shareddir = $ARGV[2];
my $spooldir = $ARGV[3];

print "Mode: $mode, user: $user, shareddir: $shareddir and spooldir: $spooldir\n";
# Set some defaults if we didn't get them
unless ($mode == 0) {
	# mode 0 = active/passive, mode 1 = active/active
	print "Mode not set on command line, going to active/active\n";
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
my $activesharedcronfile = "$sharedcrondir/$user";
my $activecronfile = "$sharedcrondir/$user.active";
my $passivesharedcronfile = "$sharedcrondir/$user.passive";
my $oldactivesharedcronfile = "$sharedcrondir/$user.old";
my $oldpassivesharedcronfile = "$sharedcrondir/$user.passive.old";
my $electiondir = "$sharedcrondir/election";
my $hostname = hostname;
my $time = time;


print "Host: $hostname started run at: $time\n";

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
		#  If it has been active in the last 120 seconds it is eligable
		my $diff = $time - $node->{'time'};
		if( $diff < 120 ) {
			print "Node: $node->{'name'} was active last 120 sec\n";
			# Go to passive mode if the numeric of that host is less than that of this host
			my $this = get_numeric($hostname);
			my $that = $node->{'numeric'};
			print "Numeric for $hostname is $this and for $node->{'name'} is $that\n";
			if( $this > $that ) {
				$state = 0 ;
				print "I am not active\n";
			} else {
				print "I am active\n";
			}
		} else {
			print "Node: $node->{'name'} was not active last 120 sec\n";

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
	print "Commenting out, infile is $infile and outfile is $outfile\n";
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
	print "Unommenting, infile is $infile and outfile is $outfile\n";
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

sub compare_and_copy {
	my ($shared, $old, $cron) = @_;
	unless ($cron) {
		$cron = $cronfile;
	}
	print "Comparing files\n";
        # If we don't have any cronjob on this host
        unless (-e $cron) {
		print "There is no cronfile on this host\e";
                # If we have a cronjob on the shared drive
                if (-e $shared) {
			print "We have a shared cronfile\n";
                        copy($shared, $cron) or die "Copy failed: $!";
			# If we dont have an old file
			unless (-e $old) {
				print "We dont have an old file so creating one\n";
				copy($shared, $old) or die "Copy failed: $!";
			}
                }
                # Nothing to do, no cronjob on any host
                return;
        }

        # If there is no cronjob on the shared drive
        unless (-e $shared) {
	
		print "There is no shared cronjobs\n";
                # But we have a cronjob on this host
                if (-e $cron) {
			print "We have some cronjobs\n";
                        copy($cron, $shared) or die "Copy failed: $!";
			# If we dont have an old file
			unless (-e $old) {
				print "There is no old cron job here som fixing that\n";
				copy($cron, $old) or die "Copy failed: $!";
			}

                }
                return;
        }

        # Current cronfile and shared cronfile is not same
        if(compare($cron, $shared) != 0) {

		print "Current cronfile and shared is not the same\n";

                # This means that the other node has changed the cron file
                if(compare($cron, $old) == 0) {
		
			print "Some othe rnode has changed the cron file\n";
                        copy($shared, $cron) or die "Copy failed: $!";
                        copy($shared, $old) or die "Copy failed: $!";
                        # All files are now the same
                # This means that my node has changed the cron file
                } else {
		
			print "This node has changed the cron file\n";
                        copy($cron, $shared) or die "Copy failed: $!";
                        # The other node will now detect the difference and do the correct adjustment
                }
        }

}

# If we are running in active/passive mode
if($mode == 0) {
	unless (-d $electiondir) {
		mkdir $electiondir;
	}

	# Update timestamp
	write_timestamp;

	# See if I am the one
	if (is_active(get_nodes) ){
		# first we comment out my cronfile and put it at activecronfile 
		comment_out($cronfile, $activecronfile);
		# Then we compare it to the oldactivesharedcronfile
		compare_and_copy($activesharedcronfile, $oldactivesharedcronfile, $activecronfile );
		# Now we compare the result of that to passivesharedcronfile
		compare_and_copy($activesharedcronfile, $passivesharedcronfile, $activecronfile);
		# Lastly we activate the result of that
		uncomment($activesharedcronfile, $cronfile);

	} else {
		compare_and_copy($passivesharedcronfile, $oldpassivesharedcronfile);
		comment_out($passivesharedcronfile, $cronfile);
		uncomment($passivesharedcronfile, $activesharedcronfile);
	}

}

# If we are running in active/active mode
else {
	compare_and_copy($activesharedcronfile, $oldactivesharedcronfile);
}

exit;
