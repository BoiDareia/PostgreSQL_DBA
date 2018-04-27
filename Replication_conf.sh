## postgresql.conf no master:

# The WAL level should be hot_standby or logical.
wal_level = logical

# Allow up to 8 standbys and backup processes to connect at a time.
max_wal_senders = 8

wal_keep_segments = 50          # in logfile segments, 16MB each; 0 disables
#wal_sender_timeout = 60s       # in milliseconds; 0 disables

max_replication_slots = 10 

# Retain 1GB worth of WAL files. Adjust this depending on your transaction rate.
max_wal_size = 1GB

## Criar user para replicação

postgres=# create user repluser replication;

## Criar BD de teste para ver replicada
postgres=# CREATE DATABASE teste_rep_db;

postgres=# \c teste_rep_db;

postgres=# CREATE TABLE teste_tbl (
     id text PRIMARY KEY,
     name text NOT NULL,
     creation_date timestamptz NOT NULL DEFAULT now()
    );
	
postgres=# INSERT INTO teste_tbl(id, name) VALUES('1', 'Sergio');

teste_rep_db=# select * from teste_tbl;


  id         | name    | creation_date          
------------ | ------- | ----------------------------- 
     1       | Sergio  | 2018-01-15 15:09:13.165883+00 
(1 row)

## Parar instância no Slave 

pg_ctl stop -D $PGDATA

## No Slave fazer um backup ao Master e importá-lo 

pg_basebackup -h machine.telecom.com -U repluser -Ft -X fetch -D - > /tmp/backup.tar

rm -rf /postgresql/itsm/data/*

tar x -v -C /postgresql/itsm/data -f /tmp/backup.tar

rm /tmp/backup.tar

## Criação do ficheiro recovery.conf no Slave para ligação ao Master
$ vi $DATADIR/recovery.conf

# This tells the slave to keep pulling WALs from master.
standby_mode = on

# This is how to connect to the master.
primary_conninfo = 'host=machine.telecom.Com user=repluser'

## Iniciar instância no Slave 

pg_ctl start -D $PGDATA

## Teste no Slave

postgres=# select pg_is_in_recovery();
 pg_is_in_recovery
-------------------
 t
(1 row)

postgres=# create database testme;
ERROR:  cannot execute CREATE DATABASE in a read-only transaction

##Verificar log após inicio de instância, deverá ter:

2018-01-15 15:37:18.000 WET [80478]: [2-1] user=,db=,app=,client=,sid=5a5ccaad.13a5e LOG:  entering standby mode
2018-01-15 15:37:18.003 WET [80478]: [3-1] user=,db=,app=,client=,sid=5a5ccaad.13a5e LOG:  redo starts at 0/4000028
2018-01-15 15:37:18.004 WET [80478]: [4-1] user=,db=,app=,client=,sid=5a5ccaad.13a5e LOG:  consistent recovery state reached at 0/40000F8
2018-01-15 15:37:18.004 WET [80476]: [6-1] user=,db=,app=,client=,sid=5a5ccaad.13a5c LOG:  database system is ready to accept read only connections
2018-01-15 15:37:18.012 WET [80482]: [1-1] user=,db=,app=,client=,sid=5a5ccaae.13a62 LOG:  started streaming WAL from primary at 0/5000000 on timeline 1




