MAILTO=""
PATH=/postgresql/basedir/bin:/bin:/sbin:/usr/bin:/usr/sbin

## Postgresql local backups
#00 08 * * * gbd_run_script.sh gbd_backup_postgresql.sh -n 3 -w basebackup >> /postgresql/itsm_repl_prd/logs/gbd_backup_postgresql_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1
#00 10 * * 6 gbd_run_script.sh gbd_backup_postgresql.sh -n 9 dumpall >> /postgresql/itsm_repl_prd/logs/gbd_backup_postgresql_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1
#31 23 * * * gbd_run_script.sh gbd_archive_config_files.sh >> /postgresql/itsm_repl_prd/logs/gbd_archive_config_files_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1

## Postgresl wal_archive remote backups
#04 * * * * gbd_run_script.sh gbd_backup_wal_archive.sh >> /postgresql/itsm_repl_prd/logs/gbd_backup_wal_archive_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1

## Script para o housekeeping da pasta wal_archive
#00 07 * * * gbd_run_script.sh gbd_pg_cleanup_archive.sh >> /postgresql/itsm_repl_prd/logs/gbd_pg_cleanup_archive_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1

## Postgresl replica monitorization
#00,15,30,45 * * * * gbd_run_script.sh gbd_monit_repl.sh >> /postgresql/itsm_prd/logs/gbd_monit_repl_itsm_prd_$(date -u +'\%Y-\%m').log 2>&1

## Check Postgresql instance logs
#*/5 * * * * gbd_run_script.sh tail_n_mail.pl --verbose /postgresql/basedir/etc/itsm_repl_prd.config.txt >> /postgresql/itsm_repl_prd/logs/tail_n_mail_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1

## Update soft link to postgres log file (workaround for OVO monitoring)
02 00 * * * gbd_run_script.sh gbd_atualiza_link_log.sh >> /postgresql/itsm_repl_prd/logs/gbd_atualiza_link_log_$(date -u +'\%Y-\%m').log 2>&1

## Get, save and send database used storage to central repository
#11 08 1 * * gbd_run_script.sh gbd_get_storage.sh >> /postgresql/itsm_repl_prd/logs/gbd_get_storage_itsm_repl_prd_$(date +'\%Y-\%m').log 2>&1

## Scripts para verificar os filesystems sgbd 
# Verificacao e envio de alertas
2,17,32,47 * * * * gbd_run_script.sh gbd_diskspace.sh /postgresql/basedir/etc/gbd_diskspace.conf >> /postgresql/itsm_repl_prd/logs/gbd_diskspace_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1
# Reset do contador de alertas
1 9 * * 1 gbd_run_script.sh gbd_diskspace_reset.sh >> /postgresql/itsm_repl_prd/logs/gbd_diskspace_itsm_repl_prd_$(date -u +'\%Y-\%m').log 2>&1

