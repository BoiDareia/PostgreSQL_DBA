#!/usr/bin/bash
#############################################################################
# Assumimos que na PATH se encontra PG_BASEDIR/bin (/postgresql/basedir/bin)
# Assumimos que existem as seguintes variaveis (definidas pelo setpg):
# GBD_FROM_EMAIL
# GBD_TO_EMAIL
# PG_BASEDIR
# PG_CLUSTER
# PG_ROOTDIR
#
# Assumimos que a lista de ficheiros a arquivar se encontra em
# PG_BASEDIR/etc
#
# 
#
#############################################################################

#### efetuar source de utilpg
. utilpg

#############################################################################
S_PROGNAME="${0##*/}"
S_HOSTNAME=$(hostname -s)

#---------------------------------------------------------------------------
# MUDAR AS PATHS DE ACORDO COM A MAQUINA/AMBIENTE
S_ERR_MSG_FILE_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/logs"
S_ERROR_MSG_FILE="${S_ERR_MSG_FILE_DIR}/${S_PROGNAME%%.*}_${PG_CLUSTER}_$(date -u +'%Y%m%dT%H%M%SZ').err"

S_WAL_ARCHIVE_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/wal_archive"

S_NETBACKUP_POLITICA="${S_HOSTNAME}_${PG_CLUSTER}_UserBck"
S_NETBACKUP_HOSTNAME="${S_HOSTNAME}.oam.ptlocal"

S_PG_FROM_EMAIL="${GBD_FROM_EMAIL}"
S_PG_TO_EMAIL="${GBD_TO_EMAIL}"
#---------------------------------------------------------------------------

#### Variaveis para verificar se o script ja se encontra a executar
S_LOCK_DIR_NAME="/tmp/${S_PROGNAME%%.*}_${PG_CLUSTER}_lock"
L_LOCK_SET_THIS_RUN=0

####  Variavel que guarda o exit code que o script vai devolver
L_EXIT_STATUS_CODE=0

#---------------------------------------------------------------------------
# Function: show_help
#
#---------------------------------------------------------------------------
show_help()
{
    cat << EOF!
Usage: ${S_PROGNAME}
Chama o cliente netbackup para efetuar backup da diretoria de arquivo
dos ficheiros wal
EOF!
}

#---------------------------------------------------------------------------
# Function: write_out
# Adiciona campos de logging ah mensagem: 
# timestamp hostname PID aplicacao tarefa nome_instancia : mensagem 
# 
# Argumentos:
# $1 - tipo de mensagem (ERROR|WARNING|INFO|FATAL|CRITICAL|DEBUG)
# $2 - mensagem
# 
#---------------------------------------------------------------------------
write_out()
{
    gbd_write_out "${S_HOSTNAME}" \
        "${PG_CLUSTER}" \
        "postgresql" \
        "${S_PROGNAME}" \
        "$1" \
        "$2"
}

#---------------------------------------------------------------------------
# Function: envia_mail
# Envia email em caso de erro/erros durante a execucao do script
#
#---------------------------------------------------------------------------
envia_mail()
{
    if [ -z "${S_PG_TO_EMAIL}" ]; then
        ## O endereco de email esta vazio, escrever mensagem para output e ficheiro de erro
        write_out "ERROR" "Nao foi encontrado endereco de email para enviar alerta (setpg)." | tee -a "${S_ERROR_MSG_FILE}"
    else
        /usr/sbin/sendmail -t << EOF!
FROM: ${S_PG_FROM_EMAIL}
TO: ${S_PG_TO_EMAIL}
SUBJECT: ERRO - falhou backup dos wals no ${S_HOSTNAME}

This is an automatic generated mail created by the 
${S_PROGNAME} script at host ${S_HOSTNAME}
------------------------------------------------------------------

falhou backup dos wals.

DATETIME: $(date -u +'%Y%m%dT%H%M%SZ')

$(cat ${S_ERROR_MSG_FILE})    
 
------------------------------------------------------------------
.
EOF!
    fi
}

#-------------------------------------------------------------------------
# Function: script_cleanup
# Efetua a remocao da diretoria de lock
#
#-------------------------------------------------------------------------
function script_cleanup
{
    ## Limpar diretoria de lock
    gbd_cleanup_lock "${S_LOCK_DIR_NAME}" ${L_LOCK_SET_THIS_RUN} 
    write_out "INFO" "Fim da execucao do script [${S_PROGNAME}]."
    exit ${L_EXIT_STATUS_CODE}
}

#############################################################################
# Bloco principal do script

## Indicar inicio da execucao
write_out "INFO" "Inicio da execucao do script [${S_PROGNAME}]."
trap script_cleanup EXIT

## Usar um ciclo for que executa apenas 1 vez para no final verificar
## se eh necessario enviar alerta. O ciclo permite o uso de "break" 
## para parar execucao e enviar alerta.
for thisexecution in runonetime; do
    
    ## Verificar se PG_CLUSTER, PG_ROOTDIR, PG_BASEDIR existem (definido pelo setpg)
    if [ -z "${PG_CLUSTER}" ] || [ -z "${PG_ROOTDIR}" ] || [ -z "${PG_BASEDIR}" ] || [ -z "${PG_DIR}" ]; then
        ## Provavelmente nao foi efetuado o setpg 
        S_ERROR_MSG_FILE="/tmp/${S_PROGNAME%%.*}_$$_$(date -u +'%Y%m%dT%H%M%SZ').err"
        write_out "ERROR" "Nao foi encontrado valor de uma das variaveis PG_CLUSTER, PG_ROOTDIR, PG_BASEDIR, PG_DIR (setpg)." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=101
        break        
    fi
    
    ## Mudar mascara dos ficheiros para novos ficheiros nao terem permissoes
    ## para group e others
    umask 0077
    if [ $? -ne 0 ]; then
        write_out "ERROR" "Nao foi possivel mudar a mascara para 0077." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=101
        break
    fi

    # Usar mkdir para testar se existe alguma execucao anterior do script.
    # mkdir eh uma operacao "atomica", 2 scripts a executar ao "mesmo" tempo,
    # apenas 1 deles vai conseguir criar a diretoria.
    if ! mkdir "${S_LOCK_DIR_NAME}" 2>/dev/null; then
        # Diretoria de lock ja existe. Escrever mensagem e sair.
        write_out "WARNING" "Diretoria de lock [${S_LOCK_DIR_NAME}] ja existe." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=101
        break
    else
        # Foi criada a diretoria de lock, colocar a variavel de controlo a 1
        # para que a funcao de cleanup remova a diretoria no fim.
        L_LOCK_SET_THIS_RUN=1
    fi
    
    #########################################################################
    ## ACTIONS BLOCK START
    #########################################################################

    ## Efetuar a mudanca de wal
    #psql -c "SELECT pg_switch_xlog();" postgres
    #psql -c "SELECT pg_switch_wal();" postgres
    psql -c "SELECT 1 AS status;" postgres
    L_PSQL_EXIT_CODE=$?
    if [ ${L_PSQL_EXIT_CODE} -ne 0 ]; then
        write_out "ERROR" "Erro ao efetuar a mudanca de WAL, exit code: [${L_PSQL_EXIT_CODE}]." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=102
        break
    else
        write_out "INFO" "Efetuada a mudanca de WAL."
        sleep 5
    fi
    L_BACKUP_DATETIME_LABEL=$(date -u +'%Y%m%dT%H%M')
    ## Efetuar o backup da diretoria de wal_archive
    L_CMD_STR="/usr/openv/netbackup/bin/bpbackup -w"
    L_CMD_STR="${L_CMD_STR} -k \"${PG_CLUSTER}_wal_archive_${L_BACKUP_DATETIME_LABEL}\""
    L_CMD_STR="${L_CMD_STR} -L \"/usr/openv/netbackup/logs/user_ops/${PG_CLUSTER}_wal_archive_backup_$(date -u +'%Y%m%d').log\" -en"
    L_CMD_STR="${L_CMD_STR} -p \"${S_NETBACKUP_POLITICA}\""
    L_CMD_STR="${L_CMD_STR} -h \"${S_NETBACKUP_HOSTNAME}\""
    L_CMD_STR="${L_CMD_STR} \"${S_WAL_ARCHIVE_DIR}\""
    
    write_out "INFO" "Comando netbackup: [${L_CMD_STR}]."

    /usr/openv/netbackup/bin/bpbackup -w \
    -k "${PG_CLUSTER}_wal_archive_${L_BACKUP_DATETIME_LABEL}" \
    -L "/usr/openv/netbackup/logs/user_ops/${PG_CLUSTER}_wal_archive_backup_$(date -u +'%Y%m%d').log" -en \
    -p "${S_NETBACKUP_POLITICA}" \
    -h "${S_NETBACKUP_HOSTNAME}" \
    "${S_WAL_ARCHIVE_DIR}/"
    
    L_NETBACKUP_EXIT_CODE=$?
    if [ ${L_NETBACKUP_EXIT_CODE} -ne 0 ]; then
        write_out "ERROR" "Erro ao efetuar backup dos WAL [${S_WAL_ARCHIVE_DIR}] , exit code: [${L_NETBACKUP_EXIT_CODE}]." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=103
        break
    else
        write_out "INFO" "Efetuado backup dos WAL [${S_WAL_ARCHIVE_DIR}]."
        
        L_CMD_STR="/usr/openv/netbackup/bin/bplist"
        L_CMD_STR="${L_CMD_STR} -C \"${S_NETBACKUP_HOSTNAME}\""
        L_CMD_STR="${L_CMD_STR} -F -keyword \"${PG_CLUSTER}_wal_archive_${L_BACKUP_DATETIME_LABEL}\"" 
        L_CMD_STR="${L_CMD_STR} -k \"${S_NETBACKUP_POLITICA}\"" 
        L_CMD_STR="${L_CMD_STR} -l -b \"${S_WAL_ARCHIVE_DIR}/*\""
        
        write_out "INFO" "Comando para listar ficheiros deste backup: [${L_CMD_STR}]"
        
        L_CMD_STR="/usr/openv/netbackup/bin/bprestore -w -t 0 -print_jobid"
        L_CMD_STR="${L_CMD_STR} -C \"${S_NETBACKUP_HOSTNAME}\""
        L_CMD_STR="${L_CMD_STR} -L \"/usr/openv/netbackup/logs/user_ops/${PG_CLUSTER}_wal_archive_restore_$(date -u +'%Y%m%d').log\" -en"
        L_CMD_STR="${L_CMD_STR} -k \"${PG_CLUSTER}_wal_archive_${L_BACKUP_DATETIME_LABEL}\""
        L_CMD_STR="${L_CMD_STR} \"${S_WAL_ARCHIVE_DIR}\""
        
        write_out "INFO" "Comando para efetuar o restore: [${L_CMD_STR}]"

    fi
    
    #########################################################################
    ## ACTIONS BLOCK END
    #########################################################################

done

## Verificar se deve enviar alerta
if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
    envia_mail
fi
