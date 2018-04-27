# PostgreSQL_DBA
Some random scripts that I use as a DBA admin Here is the general description of each one.

## Replication_conf.sh
Example of a configuration of a replication (master/slave).

## postgresql.sh
Init.d service script example.

## etc/gbd_diskspace.conf
Configuration file for the script that's in bin/gbd_diskspace.sh with the thresholds for the fyle system.

## etc/pg_config_files_INSTANCIA.lst
List of PostgreSQL configuration files to backup.

## etc/server_list_pg.lst
Configuration file that has all instances information in the machine so environment can be changed from instance to instance.

## bin/envpg
It's a centralized place to get all the variables defined so that the other scripts don't have redundant information.

## bin/gbd_archive_config_files.sh
Script to archive postgreSQL configuration files.

## bin/gbd_archive_wal.sh
It archives wal files with rsync.

## bin/gbd_atualiza_link_log.sh
Updates the log name soft link so we can keep up to 6 months worth of separate logging.

## bin/gbd_backup_postgresql.sh
Basically prepares and does the pg_basebackup and pg_dumpall of the instance to a specific fyle system, cleaning up older backups to save space - remenber to backup the backups, always...in this case it is made with another tool (netbackup, rsync, etc)

## bin/gbd_backup_wal_archive.sh
As the name suggests, it rotates wals and does a generic backup using wal_archive and Netbackup client. But it can be adapted to several other types of backups.

## bin/gbd_diskspace.crontab
Example of crontab configuration for the gbd_diskspace.sh script.

## bin/gbd_diskspace.sh
Checks database fylesystem and sends notices accordingly .

## bin/gbd_diskspace_logs_gzip.sh
For compressing log files to save storage space.

## bin/gbd_diskspace_reset.sh
Reset diskspace counters.

## bin/gbd_monitor_hotstandby_v9x.sh
Script to monitor hotstandy replication between master/slave.

## bin/gbd_pg_cleanup_archive.sh
To automatically execute the pg_archivecleanup client.

## bin/gbd_replication_diff.sh
It executes the gbd_monitor_hotstandby_v9x.sh script with some parameters.

## bin/gbd_run_all_postgres.sh


## bin/gbd_run_script.sh
I just use this to validate, within a cluster, whether the FileSystem is mounted or not since our FS changes nodes has an High Availability standard. Used in crontab to check if it should run the jobs or not, depending on if it's the active or passive node.

## bin/setpg
A script that lets you automatically set environment variables according to the instance you choose whithin the same server.

## bin/utilpg
It adds logging parameters to messages generate by the other scripts.
