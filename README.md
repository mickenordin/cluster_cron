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

## Modes
In mode 0 (active/passive) only one of the servers are active and the cron entries are commented out on the other servers. You can still edit the crontab on all servers, but cronjobs will only run on the active node

In mode 1 (active/active) the cron file will be the same on all servers and all cronjobs will run everywhere. 

If you need som cronjobs to only run in one server and some cronjobs to run on all you can add two entries to the crontab of root on all severs but using different users (called "passive" and "active" in the example below) and differernt modes, e.g.:

```
* * * * * /usr/local/bin/cluster_cron.pl passive /mnt/shareddir 0 /var/spool/cron/crontabs  >> /mnt/shareddir/cluster_passive.log 2>&1
* * * * * /usr/local/bin/cluster_cron.pl active /mnt/shareddir 1 /var/spool/cron/crontabs  >> /mnt/shareddir/cluster_active.log 2>&1
```

## Caveates

This setup should work on any number of nodes in theory, but it has only been tested on two nodes.

The syncing of cronfiles between the nodes will only happen once every ten seconds which means that there is a race condition if the cron file is updated on multiple hosts at once. Please make sure that no one else is updating th cronfile on another node at the exact same time as you are.
