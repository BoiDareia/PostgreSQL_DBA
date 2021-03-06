#! /bin/sh

# chkconfig: 2345 98 02
# description: PostgreSQL RDBMS

# This is an example of a start/stop script for SysV-style init, such
# as is used on Linux systems.  You should edit some of the variables
# and maybe the 'echo' commands.
#
# Place this file at /etc/init.d/postgresql (or
# /etc/rc.d/init.d/postgresql) and make symlinks to
#   /etc/rc.d/rc0.d/K02postgresql
#   /etc/rc.d/rc1.d/K02postgresql
#   /etc/rc.d/rc2.d/K02postgresql
#   /etc/rc.d/rc3.d/S98postgresql
#   /etc/rc.d/rc4.d/S98postgresql
#   /etc/rc.d/rc5.d/S98postgresql
# Or, if you have chkconfig, simply:
# chkconfig --add postgresql
#
# Proper init scripts on Linux systems normally require setting lock
# and pid files under /var/run as well as reacting to network
# settings, so you should treat this with care.

# Original author:  Ryan Kirkpatrick <pgsql@rkirkpat.net>

# contrib/start-scripts/linux

## EDIT FROM HERE

# Installation prefix
prefix=/postgres/basedir/pgsql101

# Data directory
PGDATA="/postgres/itsm/data"

# Who to run the postmaster as, usually "postgres".  (NOT "root")
PGUSER=postgres

# Where to keep a log file
PGLOG="/postgres/itsm/logs/itsm_console.log"

# It's often a good idea to protect the postmaster from being killed by the
# OOM killer (which will tend to preferentially kill the postmaster because
# of the way it accounts for shared memory).  To do that, uncomment these
# three lines:
PG_OOM_ADJUST_FILE=/proc/self/oom_score_adj
PG_MASTER_OOM_SCORE_ADJ=-1000
PG_CHILD_OOM_SCORE_ADJ=0
# Older Linux kernels may not have /proc/self/oom_score_adj, but instead
# /proc/self/oom_adj, which works similarly except for having a different
# range of scores.  For such a system, uncomment these three lines instead:
#PG_OOM_ADJUST_FILE=/proc/self/oom_adj
#PG_MASTER_OOM_SCORE_ADJ=-17
#PG_CHILD_OOM_SCORE_ADJ=0

## STOP EDITING HERE

# The path that is to be used for the script
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# What to use to start up the postmaster.  (If you want the script to wait
# until the server has started, you could use "pg_ctl start -w" here.
# But without -w, pg_ctl adds no value.)
DAEMON="$prefix/bin/pg_ctl"

# What to use to shut down the postmaster
PGCTL="$prefix/bin/pg_ctl"

set -e

# Only start if we can find the postmaster.
test -x $DAEMON ||
{
    echo "$DAEMON not found"
    #if [ "$1" = "stop" ]; then
    #    exit 0
    if [ "$1" = "status" ]; then
        exit 3
    else
        exit 5
    fi
}

# If we want to tell child processes to adjust their OOM scores, set up the
# necessary environment variables.  Can't just export them through the "su".
if [ -e "$PG_OOM_ADJUST_FILE" -a -n "$PG_CHILD_OOM_SCORE_ADJ" ]; then
    DAEMON_ENV="PG_OOM_ADJUST_FILE=$PG_OOM_ADJUST_FILE PG_OOM_ADJUST_VALUE=$PG_CHILD_OOM_SCORE_ADJ"
fi

# Script exit status
L_SCRIPT_STATUS=0

# Parse command line parameters.
case $1 in
    start)
        echo -n "Starting PostgreSQL: "
        test -e "$PG_OOM_ADJUST_FILE" && echo "$PG_MASTER_OOM_SCORE_ADJ" > "$PG_OOM_ADJUST_FILE"
        # Do not exit in return code != 0
        set +e
        su - $PGUSER -c "$PGCTL status -D '$PGDATA'"
        L_EXIT_STATUS=$?
        if [ $L_EXIT_STATUS -eq 0 ]; then
            # Postgresql is already running
            echo "ok, postgresql is already running."
        else
            # Postgresql is not running. Start service.
            su - $PGUSER -c "$DAEMON_ENV $DAEMON start -D '$PGDATA' -l ${PGLOG} 2>&1"
            L_EXIT_STATUS=$?
            if [ $L_EXIT_STATUS -eq 0 ]; then
                # Postgresql was started successfully
                echo "ok."
            else
                echo "nok. Unknown error while starting."
            fi
        fi
        L_SCRIPT_STATUS=$L_EXIT_STATUS
        ;;
    stop)
        echo -n "Stopping PostgreSQL: "
        # Do not exit in return code != 0
        set +e
        su - $PGUSER -c "$PGCTL status -D '$PGDATA'"
        L_EXIT_STATUS=$?
        if [ $L_EXIT_STATUS -eq 3 ]; then
            # Postgresql is already stopped.
            echo "ok, postgresql was already stopped."
            # Change exit status to 0, lsb conformant.
            L_EXIT_STATUS=0
        else
            if [ $L_EXIT_STATUS -eq 0 ]; then
                # Postgresql is running, stop service.
                su - $PGUSER -c "$PGCTL stop -D '$PGDATA' -s -m fast"
                L_EXIT_STATUS=$?
                if [ $L_EXIT_STATUS -eq 0 ]; then
                    # Postgresql was stopped successfully.
                    echo "ok."
                else
                    # Error while stopping postgresql.
                    echo "nok. Unknown error while stopping."
                fi
            else
                # Postresql status is unknown. Do nothing.
                echo "nok. Unknown service status."
            fi
        fi
        L_SCRIPT_STATUS=$L_EXIT_STATUS
        ;;
  restart)
        echo -n "Restarting PostgreSQL: "
        # Do not exit in return code != 0
        set +e
        su - $PGUSER -c "$PGCTL restart -D '$PGDATA' -l ${PGLOG} -s -m fast -w"
        L_EXIT_STATUS=$?
        if [ $L_EXIT_STATUS -eq 0 ]; then
            # Postgresql restart was successful.
            echo "ok."
        else
            # Postgresql restart was not successful.
            echo "nok, failed to restart postgresql."
        fi
        L_SCRIPT_STATUS=$L_EXIT_STATUS
        ;;
  reload)
        echo -n "Reload PostgreSQL: "
        # Do not exit in return code != 0
        set +e
        su - $PGUSER -c "$PGCTL reload -D '$PGDATA' -s"
        L_EXIT_STATUS=$?
        if [ $L_EXIT_STATUS -eq 0 ]; then
            # Postgresql reload was successful.
            echo "ok."
        else
            # Postgresql reload was not successful.
            echo "nok, failed to reload config files."
        fi
        L_SCRIPT_STATUS=$L_EXIT_STATUS
        ;;
  status)
        # Do not exit in return code != 0
        set +e
        su - $PGUSER -c "$PGCTL status -D '$PGDATA'"
        L_EXIT_STATUS=$?
        if [ $L_EXIT_STATUS -eq 0 ]; then
            # Postgresql status is running.
            echo "Postgresql is running."
        else
            # Postgresql status is not running.
            echo "Postgresql is not running."
        fi
        L_SCRIPT_STATUS=$L_EXIT_STATUS
        ;;
  *)
        # Print help
        echo "Usage: $0 {start|stop|restart|reload|status}" 1>&2
        L_SCRIPT_STATUS=1
        ;;
esac

exit $L_SCRIPT_STATUS
