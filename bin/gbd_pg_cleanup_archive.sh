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

#############################################################################
S_PROGNAME="${0##*/}"
S_HOSTNAME=$(hostname -s)

#---------------------------------------------------------------------------
# MUDAR AS PATHS DE ACORDO COM A MAQUINA/AMBIENTE
S_ERR_MSG_FILE_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/logs"
S_ERROR_MSG_FILE="${S_ERR_MSG_FILE_DIR}/${S_PROGNAME%%.*}_${PG_CLUSTER}_$(date -u +'%Y%m%dT%H%M%SZ').err"
S_WAL_ARCHIVE_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/wal_archive"

S_PG_FROM_EMAIL="${GBD_FROM_EMAIL}"
S_PG_TO_EMAIL="${GBD_TO_EMAIL}"

## Manter ficheiros WAL com menos de X dias
S_DAYS_TO_KEEP_ARCHIVES=5

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
Usage: ${S_PROGNAME} [-h] [-n DAYS]
Utiliza pg_archivecleanup para remover ficheiros WAL mais antigos que
DAYS dias.

    -h|-?|--help    Mostrar este texto e sair do script
    -n DAYS         Encontrar ficheiros .backup mais antigos que DAYS e usar
                    pg_archivecleanup para remover WALs a partir desse 
                    ficheiro
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
SUBJECT: ERRO - falhou a limpeza do arquivo de ficheiros WAL no ${S_HOSTNAME}

This is an automatic generated mail created by the 
${S_PROGNAME} script at host ${S_HOSTNAME}
------------------------------------------------------------------

falhou a limpeza do arquivo de ficheiros WAL.

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

    
    ## Verificar se PG_CLUSTER existe (definido pelo setpg)
    if [ -z "${PG_CLUSTER}" ] || [ -z "${PG_ROOTDIR}" ] || [ -z "${PG_BASEDIR}" ] || [ -z "${PG_DIR}" ]; then
        ## Provavelmente nao foi efetuado o setpg 
        S_ERROR_MSG_FILE="/tmp/${S_PROGNAME%%.*}_$$_$(date -u +'%Y%m%dT%H%M%SZ').err"
        write_out "ERROR" "Nao foi encontrado valor de uma das variaveis PG_CLUSTER, PG_ROOTDIR, PG_BASEDIR, PG_DIR (setpg)." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=101
        break        
    fi

    ## Ler argumentos
    ## Inicializar as variavies que dependem de argumentos passados ao script.
    ## Isto garante que esta variaveis nao veem com valores modificados.
    L_DAYS_TO_KEEP_ARCHIVES=${S_DAYS_TO_KEEP_ARCHIVES}
    ## Usar um ciclo para ler os argumentos passados e fazer validacao
    while :; do
        case $1 in
            -h|-\?|--help)
                show_help
                exit
                ;;
            -n)       # Takes an option argument; ensure it has been specified.
                if [ "$2" ]; then
                    L_DAYS_TO_KEEP_ARCHIVES=$2
                    shift
                    ## Verificar que eh um numero inteiro
                    case $L_DAYS_TO_KEEP_ARCHIVES in
                        ''|*[!0-9]*) 
                            write_out "ERROR" "\"-n\" necessita de um argumento valido (numero inteiro) [${L_DAYS_TO_KEEP_ARCHIVES}]." | tee -a "${S_ERROR_MSG_FILE}"
                            L_EXIT_STATUS_CODE=101
                            break 2
                            ;;
                        *) 
                            ## Nao fazer nada, eh um inteiro
                            write_out "INFO" "Numero de dias a manter: [${L_DAYS_TO_KEEP_ARCHIVES}]."
                            ;;
                    esac
                else
                    write_out "ERROR" "\"-n\" necessita de um argumento (inteiro) nao vazio." | tee -a "${S_ERROR_MSG_FILE}"
                    L_EXIT_STATUS_CODE=101
                    break 2
                fi
                ;;
            -?*)
                write_out "WARNING" "Argumento desconhecido (ignorado): [$1]." >&2
                ;;
            *)               # Default case: No more options, so break out of the loop.
                break
                ;;
        esac
        shift
    done
    
    ## Mudar mascara dos ficheiros para novos ficheiros nao terem permissoes para group e others
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
    ## START ACTIONS HERE
    #########################################################################

    ## Ficheiro para guardar os resultados do find.
    S_FILE_LIST_FULLPATH="${S_LOCK_DIR_NAME}/gbd_pg_cleanup_archive.lst"
    ## Efetuar o find .
    ## Mudar para S_WAL_ARCHIVE_DIR
    cd "${S_WAL_ARCHIVE_DIR}"
    L_CMD_EXIT_STATUS=$?
    if [ $L_CMD_EXIT_STATUS -ne 0 ]; then
        write_out "ERROR" "Erro ao efetuar mudanca para diretoria [${S_WAL_ARCHIVE_DIR}], exit code: [${L_CMD_EXIT_STATUS}]." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=102
        break
    fi

    ## Find older ,backup wall
    find . -name '*.backup' -type f -mtime +$L_DAYS_TO_KEEP_ARCHIVES -printf '%f\n' > "${S_FILE_LIST_FULLPATH}"
    L_CMD_EXIT_STATUS=$?
    if [ ${L_CMD_EXIT_STATUS} -ne 0 ]; then
        write_out "ERROR" "Erro ao efetuar o find de WAL.backup na diretoria  [${S_WAL_ARCHIVE_DIR}], exit code: [${L_CMD_EXIT_STATUS}]." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=103
        break
    fi
    ## Get files with higher numbering
    L_TARGET_WAL_BACKUP=$(sort "${S_FILE_LIST_FULLPATH}" | tail -1) 
    if [ -z "${L_TARGET_WAL_BACKUP}" ]; then
        write_out "INFO" "Nao foi encontrado nenhum WAL.backup na diretoria [${S_WAL_ARCHIVE_DIR}] com mais do que [${L_DAYS_TO_KEEP_ARCHIVES}] dias."
        break
    else
        write_out "INFO" "Ficheiro WAL.backup encontrado: [${L_TARGET_WAL_BACKUP}]."
    fi 
    
    ## Chamar o binario de cleanup
    #pg_archivecleanup -n -d "${S_WAL_ARCHIVE_DIR}" "${L_TARGET_WAL_BACKUP}"
    pg_archivecleanup -d "${S_WAL_ARCHIVE_DIR}" "${L_TARGET_WAL_BACKUP}"
    L_CMD_EXIT_STATUS=$?
    if [ ${L_CMD_EXIT_STATUS} -ne 0 ]; then
        write_out "ERROR" "Erro ao chamar o binario de cleanup wal [${S_WAL_ARCHIVE_DIR}], exit code: [${L_CMD_EXIT_STATUS}]." | tee -a "${S_ERROR_MSG_FILE}"
        L_EXIT_STATUS_CODE=104
        break
    else
        write_out "INFO" "Efetuado cleanup dos WAL [${S_WAL_ARCHIVE_DIR}]."
    fi

    
    #########################################################################
    ## STOP ACTIONS HERE
    #########################################################################

done

## Verificar se deve enviar alerta
if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
    envia_mail
fi
