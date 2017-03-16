#!/usr/bin/perl

use strict;
use warnings;
use Config::JSON;
use DBI;
use File::Compare;
use File::Copy;
use Sys::Hostname;

$| = 1;

# Read config file
my $config_file = $ARGV[0];

my $config      = Config::JSON->new($config_file) or die "Can not open config file: $config_file";

my $crontab       = $config->get('crontabs');
my $sharedcrontab = $config->get('sharedcrontab');
my $masterfile    = $config->get('masterfile');


my $i = `hostname --fqdn`;
chomp $i;
my $apacheuid = 33;
my $crongid = 107;

# Connect to the dabase and see which one icinga thinks is the master
sub get_master_from_db {
	# Setting up for db query
	my $database      = $config->get('db');
	my $db_host       = $config->get('host');
	my $db_user       = $config->get('user');
	my $db_password   = $config->get('password');

    my $connect = DBI->connect( "DBI:mysql:database=$database;host=$db_host",
        $db_user, $db_password, { RaiseError => 1 } );
    my $query =
      $connect->prepare("SELECT endpoint_name FROM icinga_programstatus");
    $query->execute();

    my $active = $query->fetchrow();
    return $active;
}

# See what the file sais about who is master
sub get_master_from_file {

    open( my $fh, '<:encoding(UTF-8)', $masterfile )
      or die "Could not open file '$masterfile' $!";

    my $master = <$fh>;
    close($fh);
    chomp $master;

    return $master;

}

# update the file with current master
sub set_master_in_file {
    open( my $fh, '>', $masterfile )
      or die "Could not open file '$masterfile' $!";
    print $fh $i;
    close $fh;
}

# See if I am master
sub is_active {
    my ($master) = @_;
    my $status = 0;

    if ( $i eq $master ) {
        $status = 1;
    }

    return $status;
}

# Do the work
sub run {
    print "Starting run at $i.\n";
    # See if I am active as far as Icinga is concerned
    if (is_active(get_master_from_db)) {
        print "Icinga sais that I am master.\n";
        # See if I am active as far as the file thinks
        if (is_active(get_master_from_file)) {
            print "No failover has happened.\n";
            # See if the crontab has changed
            if (compare( $crontab, $sharedcrontab ) != 0) {
                print "The cronfile has changed, copying it to the shared drive.\n";
                # Copy the crontab to the shared file if it has changed
                copy( $crontab, $sharedcrontab );
                chown $apacheuid, $crongid, ($sharedcrontab);
            }

        }
        # If this clause executes, there has been a failover
        else {
            print "A failover has happened.\n";
            print "Installing cronfile from the shared drive.\n";
            # Copy the shared crontab to my crontab and set me as active in the file
            copy( $sharedcrontab, $crontab );
            chown $apacheuid, $crongid, ($crontab);
            set_master_in_file;
        }

    }
    # If this clause executes, I am not the master
    else {
        print "Icinga sais I am not master.\n";
        # Remove the cronfile
        if( -e $crontab) {
            print "A failover has happened.\n";
            print "Removing crontab.\n";
            unlink $crontab;
        }
    }
}

# We want to run six times in a minute
for (my $index = 0; $index < 6; $index++) {
    my $start = time;
    run;
    if ((my $remaining = 10 - (time - $start)) > 0) {
        sleep $remaining;
    }
}
exit;
