#!/usr/bin/bash
#############################################################################
# Assumimos que na PATH se encontra PG_BASEDIR/bin (/postgresql/basedir/bin)
# Assumimos que existem as seguintes variaveis (definidas pelo setpg):
# GBD_FROM_EMAIL
# GBD_TO_EMAIL
# PG_BASEDIR
# PG_CLUSTER
# PG_ROOTDIR
# PG_DIR
#
#############################################################################

#### efetuar source de utilpg
. utilpg

S_INSTANCIA="${PG_CLUSTER}"
S_PROGNAME="${0##*/}"
S_TODAY=$(date +'%Y-%m-%d')

ln -s -f /postgresql/${S_INSTANCIA}/logs/${S_INSTANCIA}_${S_TODAY}.log /postgresql/${S_INSTANCIA}/logs/${S_INSTANCIA}.log
printf "%s %s %s %s postgresql %s : INFO : changed link [%s] to [%s].\n" \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    "$(hostname -s)" \
    "$$" \
    "${S_INSTANCIA}" \
    "${S_PROGNAME}" \
    "/postgresql/${S_INSTANCIA}/logs/${S_INSTANCIA}.log" \
    "/postgresql/${S_INSTANCIA}/logs/${S_INSTANCIA}_${S_TODAY}.log"    
