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
S_CONFIG_FILES_LIST="${PG_BASEDIR}/etc/pg_config_files_${PG_CLUSTER}.lst"
S_DESTINATION_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/backups/pg_config_files"
S_ERR_MSG_FILE_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/logs"
S_ERROR_MSG_FILE="${S_ERR_MSG_FILE_DIR}/${S_PROGNAME%%.*}_${PG_CLUSTER}_$(date -u +'%Y%m%dT%H%M%SZ').err"

S_PG_FROM_EMAIL="${GBD_FROM_EMAIL}"
S_PG_TO_EMAIL="${GBD_TO_EMAIL}"
#---------------------------------------------------------------------------

#### Variaveis para verificar se o script ja se encontra a executar
S_LOCK_DIR_NAME="/tmp/${S_PROGNAME%%.*}_${PG_CLUSTER}_lock"
L_LOCK_SET_THIS_RUN=0

####  Variavel que guarda o exit code que o script vai devolver
L_EXIT_STATUS_CODE=0

#---------------------------------------------------------------------------
# Function: print_help
#
#---------------------------------------------------------------------------
print_help()
{
    printf "${S_PROGNAME} usage: ??\n"
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
        write_out "ERROR" "Nao foi encontrado endereco de email para enviar alerta (setpg)." | tee -a "${S_ERROR_MSG_FILE}"
    else
        /usr/sbin/sendmail -t << EOF!
FROM: ${S_PG_FROM_EMAIL}
TO: ${S_PG_TO_EMAIL}
SUBJECT: ERRO - falhou a copia dos ficheiros de config no ${S_HOSTNAME}

This is an automatic generated mail created by the 
${S_PROGNAME} script at host ${S_HOSTNAME}
------------------------------------------------------------------

falhou a copia dos ficheiros de config.

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
## se eh necessario enviar alerta
for thisexecution in runonetime; do
    ## Verificar se PG_CLUSTER existe ()
    if [ -z "${PG_CLUSTER}" ] || [ -z "${PG_ROOTDIR}" ] || [ -z "${PG_BASEDIR}" ] || [ -z "${PG_DIR}" ]; then
        ## Provavelmente nao foi efetuado o setpg 
        S_ERROR_MSG_FILE="/tmp/${S_PROGNAME%%.*}_$$_$(date -u +'%Y%m%dT%H%M%SZ').err"
        write_out "ERROR" "Nao foi encontrado valor de uma das variaveis PG_CLUSTER, PG_ROOTDIR, PG_BASEDIR, PG_DIR (setpg)." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=101
        break        
    fi

    ## Mudar mascara dos ficheiros para novos ficheiros nao terem permissoes para group e others
    umask 0077
    if [ $? -ne 0 ]; then
        write_out "ERROR" "Nao foi possivel mudar a mascara para 0077." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=101
        break
    fi

    # Usar mkdir para testar se existe alguma execucao anterior do script.
    # mkdir eh uma operacao "atomica", 2 scrits a executar ao "mesmo" tempo,
    # apenas 1 deles vai conseguir criar a diretoria.
    if ! mkdir "${S_LOCK_DIR_NAME}" 2>/dev/null; then
        # Diretoria de lock ja existe. Escrever mensagem e sair.
        write_out "WARNING" "Diretoria de lock [${S_LOCK_DIR_NAME}] ja existe." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=101
        break
    else
        # Foi criada a paste de lock, colocar a variavel de controlo a 1
        # para que a funcao de cleanup remova a diretoria no fim.
        L_LOCK_SET_THIS_RUN=1
    fi
    
    ## Verificar se S_DESTINATION_DIR existe e tentar criar caso nao exista
    if [ ! -d "${S_DESTINATION_DIR}" ]; then
        ## Diretoria nao existe/nao eh uma diretoria, tentar criar
        mkdir -p "${S_DESTINATION_DIR}"
        if [ $? -ne 0 ]; then
            write_out "ERROR" "Nao foi possivel criar a diretoria [${S_DESTINATION_DIR}]." | tee -a "${S_ERROR_MSG_FILE}"
            L_EXIT_STATUS_CODE=102
            break
        else
            write_out "INFO" "Foi criada a diretoria [${S_DESTINATION_DIR}]."
        fi
    fi

    ## Verificar se existe o ficheiro de configuracao com a lista
    if [ ! -r "${S_CONFIG_FILES_LIST}" ]; then
        write_out "ERROR" "Nao foi encontrado o ficheiro [${S_CONFIG_FILES_LIST}]." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=103
        break
    fi

    ## Ler o ficheiro de configuracao que consiste numa lista de ficheiros a copiar.
    #  Cada linha deve ser o fullpathname do ficheiro a copiar
    while read -r L_FILEPATHTOCOPY; do
        ## Copiar ficheiro para diretoria destino
        if [ -n "${L_FILEPATHTOCOPY}" ]; then
            cp -p "${L_FILEPATHTOCOPY}" "${S_DESTINATION_DIR}/"
            if [ $? -ne 0 ]; then
                write_out "ERROR" "Nao foi possivel copiar o ficheiro [${L_FILEPATHTOCOPY}]." | tee -a "${S_ERROR_MSG_FILE}"
                L_EXIT_STATUS_CODE=104
            else
                write_out "INFO" "Copiado o ficheiro [${L_FILEPATHTOCOPY}] para a diretoria [${S_DESTINATION_DIR}]."
            fi
        fi
    done < "${S_CONFIG_FILES_LIST}"
done

## Verificar se deve enviar alerta
if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
    envia_mail
fi
