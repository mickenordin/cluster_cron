# cluster_cron
A perlscript that makes it possible to cluster cron via a shared drive

In order to use this you need a shared drive on all servers that is going to be part of the cluster such as afs, glusterfs, nfs or samba.

Install this script somwhere and make sure it is executable. In this example the script will be put in:
/usr/local/bin/cluster_cron.pl

Next you need to add the script to the crontab of some user which will not be synced on both servers, for example the root user.

The script takes 4 arguments of which two are optional:
user = the user that gets the cron file synced, in this example we are using a user called cluster
shared directory = the shared drive you set up previously, in this example the path is /mnt/shareddir
mode = either 0 for active/passive or 1 for active/active if this argument is not supplied 1 is assumed
cron spool directory = defaults to /var/spool/cron/crontabs

So as root:
crontab -e

add this line:
```
* * * * * /usr/local/bin/cluster_cron.pl cluster /mnt/shareddir 0 /var/spool/cron/crontabs  >> /mnt/shareddir/cluster.log 2>&1
```
