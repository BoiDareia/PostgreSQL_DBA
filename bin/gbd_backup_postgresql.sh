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
S_ERR_MSG_FILE_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/logs"
S_ERROR_MSG_FILE="${S_ERR_MSG_FILE_DIR}/${S_PROGNAME%%.*}_${PG_CLUSTER}_$(date -u +'%Y%m%dT%H%M%SZ').err"
S_PG_BASEBACKUP_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/backups/pg_basebackup"
S_PG_DUMPALL_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/backups/pg_dumpall"
S_PG_WAL_ARCHIVE_DIR="${PG_ROOTDIR}/${PG_CLUSTER}/wal_archive"

S_PG_FROM_EMAIL="${GBD_FROM_EMAIL}"
S_PG_TO_EMAIL="${GBD_TO_EMAIL}"

##  Manter backups com menos de X dias
S_DAYS_TO_KEEP_BACKUPS=5
## Flag para controlar a limpeza do arquivo de WALs
S_HOUSEKEEPING_WAL_ARCHIVE=0

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
Usage: ${S_PROGNAME} [-h] [-w] [-n DAYS] [TIPODEBACKUP]
Efetua o backup de uma instancia PostgreSQL com pg_dumpall ou 
pg_basebackup. Efetua tambem housekeeping dos backups e wals com
mais de DAYS dias.

    -h|-?|--help    Mostrar este texto e sair do script
    -w              Efetuar limpeza dos arquivos wal com mais de DAYS dias (desligado por predefinicao)
    -n DAYS         Numero de dias (5 por predefinicao) para manter backups
    TIPODEBACKUP    Valores possiveis sao "dumpall" e "basebackup"
                    dumpall    - Efetua backups logico
                    basebackup - Efetua backup fisico
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
# Assume que o comando "sendmail" se encontra na PATH
#
#---------------------------------------------------------------------------
envia_mail()
{
    if [ -z "${S_PG_TO_EMAIL}" ]; then
        ## O endereco de email esta vazio, escrever mensagem para output e ficheiro de erro
        write_out "ERROR" "Nao foi encontrado endereco de email para enviar alerta (setpg)." | tee -a "${S_ERROR_MSG_FILE}"
    else
        sendmail -t << EOF!
FROM: ${S_PG_FROM_EMAIL}
TO: ${S_PG_TO_EMAIL}
SUBJECT: ERRO - falhou backup PostgreSQL no ${S_HOSTNAME}

This is an automatic generated mail created by the 
${S_PROGNAME} script at host ${S_HOSTNAME}
------------------------------------------------------------------

falhou o backup da instancia PostgreSQL.

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

#---------------------------------------------------------------------------
# Function: delete_old_backups
# Funcao para recursivamente apagar todos os ficheiros e subdiretorias
# debaixo de uma dada diretoria com mais de X dias 
#
# Recebe 2 argumentos:
# $1 : Path base a partir da qual devem ser apagados os ficheiros
# $2 : numero de dias para poder apagar os ficheiros
#
#---------------------------------------------------------------------------
delete_old_files()
{
    write_out "INFO" "Inicio da execucao da funcao delete_old_backups."
    
    # Vamos apagar ficheiros de forma recursiva, fazer algumas verificacoes
    if [ $# -ne 2 ]; then
        # Devem ser exatamente 2 argumentos
        write_out "ERROR" "O numero de argumentos deve ser 2." | tee -a "${S_ERROR_MSG_FILE}"
        return 101
    fi
    
    if [ -z "$1" ]; then
        # Path dado esta vazio, abortar
        write_out "ERROR" "O path dado esta vazio." | tee -a "${S_ERROR_MSG_FILE}"
        return 101
    fi
    
    if [ ! -d "$1" ]; then
        # Path dado nao eh uma diretoria
        write_out "ERROR" "O path dado nao eh uma diretoria [$1]" | tee -a "${S_ERROR_MSG_FILE}"
        return 101
    fi
    
    # Usar case com expansao de padrao para fazer um teste simples para inteiros positivos
    # Tambem verificamos se o parametro esta vazio
    case "$2" in
        ''|*[!0-9]*) 
            # Numero de dias nao eh um valor valido (maior que 0)
            write_out "ERROR" "Numero de dias invalido [$2]." | tee -a "${S_ERROR_MSG_FILE}"
            return 101
            ;;
        *) 
            # Numero de dias aparenta ser um inteiro valido
            if [ $2 -le 0 ]; then
                write_out "ERROR" "Numero de dias tem de ser maior que zero [$2]." | tee -a "${S_ERROR_MSG_FILE}"
                return 101
            else
                write_out "INFO" "Numero de dias para manter os ficheiros [$2]."
            fi
            ;;
    esac
    
    # Guardar diretoria currente
    L_PREVIOUS_PWD="$(pwd)"

    # Mudar para o diretoria base
    cd "$1"
    if [ $? -ne 0 ]; then
        write_out "ERROR" "Falhou a mudanca para a diretoria [$1]." | tee -a "${S_ERROR_MSG_FILE}"
        return 102
    else
        write_out "INFO" "Pasta base para remover ficheiros [$1]."
    fi
    
    ## usar find para encontrar e remover ficheiros
    ## Os filtros do find sao uma cadeia, sao aplicados por ordem
    ## -depth      : processar conteudos das diretorias antes da diretoria em si 
    ## ! -name '.' : nao incluir a propria diretoria
    ## -mtime +XX  : nao incluir ficheiros alterados ah menos de XX dias
    find . -depth ! -name '.' -mtime +"$2" \
        -exec printf "%s %s %s %s postgresql %s : INFO : File to delete [%s].\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${S_HOSTNAME}" "$$" "${PG_CLUSTER}" "${S_PROGNAME}" '{}' ';' \
        -exec /bin/rm -rf '{}' ';'
    L_EXIT_CODE=$?
    if [ ${L_EXIT_CODE} -ne 0 ]; then
        write_out "ERROR" "Falha no comando find [${L_EXIT_CODE}]." | tee -a "${S_ERROR_MSG_FILE}"
        return 103
    else
        write_out "INFO" "find return code [${L_EXIT_CODE}]."
    fi
    # Mudar para a diretoria anteriormente guardada
    cd "${L_PREVIOUS_PWD}"
    if [ $? -ne 0 ]; then
        write_out "ERROR" "Falhou a mudanca para a diretoria [${L_PREVIOUS_PWD}]." | tee -a "${S_ERROR_MSG_FILE}"
        return 102
    fi
    write_out "INFO" "Fim da execucao da funcao delete_old_backups."
    return 0
}

#---------------------------------------------------------------------------
# Function: backup_pgbasebackup
# Recebe 1 argumento:
# 
# $1 : Diretoria de destino do backup
# 
#---------------------------------------------------------------------------
backup_pgbasebackup()
{
    ## Efetuar um pg_basebackup
    ## --wal-method=fetch  : The transaction log files are collected at the end of the backup.
    ## --format=t          : Write the output as tar files in the target directory.
    ## -R                  : Write a minimal recovery.conf  to ease setting up a standby server.
    ## --gzip              : Enables gzip compression of tar file output, with the default compression level.
    ## --checkpoint=spread : Sets checkpoint mode to spread.

    write_out "INFO" "Inicio da execucao da funcao backup_pgbasebackup para a diretoria [$1]."

    # Verificar que a diretoria destino do backups existe    
    if [ ! -d "$1" ]; then
        write_out "ERROR" "A diretoria [$1] nao existe/nao esta acessivel." | tee -a "${S_ERROR_MSG_FILE}"
        return 102
    fi
    
    ## Usar data/hora para criar nome da diretoria onde o backup vai ficar
    LOCAL_DATE_VAR=$(date +'%Y%m%dT%H%M')
    LOCAL_BACKUP_DIR="$1/${LOCAL_DATE_VAR}"
    ${PG_DIR}/bin/pg_basebackup \
        --pgdata="${LOCAL_BACKUP_DIR}" \
        --wal-method=fetch \
        --format=tar \
        --gzip \
        --checkpoint=spread \
        --label="pg_basebackup ${PG_CLUSTER} ${LOCAL_DATE_VAR}"
    L_EXIT_CODE=$?
    if [ ${L_EXIT_CODE} -ne 0 ]; then
        write_out "ERROR" "Falha a efetuar o base backup. Exit code [${L_EXIT_CODE}]." | tee -a "${S_ERROR_MSG_FILE}"
        return 103
    fi
    write_out "INFO" "Fim da execucao da funcao backup_pgbasebackup"
    return 0
}

#---------------------------------------------------------------------------
# Function: backup_pgdumpall
# Recebe 1 argumento:
# 
# $1 : Diretoria de destino do backup
# 
#---------------------------------------------------------------------------
backup_pgdumpall()
{
    ## Para cada servidor na lista, fazer um pg_dumpall
    ## --lock-wait-timeout=300 : Do not wait forever to acquire shared table locks at the beginning of the dump.
    ## --clean                 : Include SQL commands to clean (drop) databases before recreating them.
    ## --if-exists             : Use conditional commands (i.e. add an IF EXISTS clause) to clean databases and other objects.

    write_out "INFO" "Inicio da execucao da funcao backup_pgdumpall."
    # Verificar que a diretoria destino do backups existe
    LOCAL_DATE_VAR=$(date +'%Y%m%dT%H%M')
    LOCAL_BACKUP_DIR="$1/${LOCAL_DATE_VAR}"
    if [ ! -d "${LOCAL_BACKUP_DIR}" ]; then
        if ! mkdir "${LOCAL_BACKUP_DIR}" 2>/dev/null; then
            write_out "ERROR" "Erro ao tentar criar diretoria de backups [${LOCAL_BACKUP_DIR}]." | tee -a "${S_ERROR_MSG_FILE}"
            return 102
        fi
    fi  
    
    ## Usar data/hora para criar nome do ficheiro onde o backup vai ficar
    LOCAL_BACKUP_FULL_FILEPATH="${LOCAL_BACKUP_DIR}/pg_dumpall_${PG_CLUSTER}_${LOCAL_DATE_VAR}.sql"
    write_out "INFO" "Execucao do pg_dumpall para o ficheiro [${LOCAL_BACKUP_FULL_FILEPATH}]."
    ${PG_DIR}/bin/pg_dumpall \
        --file="${LOCAL_BACKUP_FULL_FILEPATH}" \
        --lock-wait-timeout=300 \
        --clean \
        --if-exists
    L_EXIT_CODE=$?
    if [ ${L_EXIT_CODE} -ne 0 ]; then
        write_out "ERROR" "Falha a efetuar o pg_dumpall [${L_EXIT_CODE}]." | tee -a "${S_ERROR_MSG_FILE}"
        return 103
    fi

    write_out "INFO" "Compressao do ficheiro de pg_dumpall [${LOCAL_BACKUP_FULL_FILEPATH}]."
    /usr/bin/gzip -f "${LOCAL_BACKUP_FULL_FILEPATH}"
    L_EXIT_CODE=$?
    if [ ${L_EXIT_CODE} -ne 0 ]; then
        write_out "ERROR" "Falha a efetuar o gzip do ficheiro [${LOCAL_BACKUP_FULL_FILEPATH}] [${L_EXIT_CODE}]." | tee -a "${S_ERROR_MSG_FILE}"
        return 103
    fi
    write_out "INFO"  "Fim da execucao da funcao backup_pgdumpall."
    return 0
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
    
    ## Verificar se PG_CLUSTER, PG_ROOTDIR, PG_BASEDIR existem 
    ## (definido pelo setpg)
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
    # Numero de dias para manter backups e WAL archive
    L_DAYS_TO_KEEP_BACKUPS=${S_DAYS_TO_KEEP_BACKUPS} 
    # Tipo de backup
    L_PG_BACKUP_TYPE=""
    # Flag para controlar a limpeza do arquivo de WALs
    L_HOUSEKEEPING_WAL_ARCHIVE=0
    ## Usar um ciclo para ler os argumentos passados e fazer validacao
    while :; do
        case $1 in
            -h|-\?|--help)
                show_help    # Display a usage synopsis.
                exit
                ;;
            -n)       # Takes an option argument; ensure it has been specified.
                if [ "$2" ]; then
                    L_DAYS_TO_KEEP_BACKUPS=$2
                    shift
                    ## Verificar que eh um numero inteiro
                    case $L_DAYS_TO_KEEP_BACKUPS in
                        ''|*[!0-9]*) 
                            write_out "ERROR" "\"-n\" necessita de um argumento valido (numero inteiro) [${L_DAYS_TO_KEEP_BACKUPS}]." | tee -a "${S_ERROR_MSG_FILE}"
                            L_EXIT_STATUS_CODE=101
                            break 2
                            ;;
                        *) 
                            ## Nao fazer nada, eh um inteiro
                            write_out "INFO" "Numero de dias a manter: [${L_DAYS_TO_KEEP_BACKUPS}]."
                            ;;
                    esac
                else
                    write_out "ERROR" "\"-n\" necessita de um argumento (inteiro) nao vazio." | tee -a "${S_ERROR_MSG_FILE}"
                    L_EXIT_STATUS_CODE=101
                    break 2
                fi
                ;;  
            -w)       # flag
                L_HOUSEKEEPING_WAL_ARCHIVE=1
                ;;                
            -?*)
                write_out "WARNING" "Argumento desconhecido (ignorado): [$1]." >&2
                ;;
            *)               # Default case: No more options, so break out of the loop.
                break
        esac
        ## Avancar para o proximo argumento
        shift
    done
    ## Todos os argumento do tipo "-X" foram lidos, verificar que tem de existir TIPODEBACKUP
    case $1 in
        dumpall)
            L_PG_BACKUP_TYPE="dumpall"
            ;;
        basebackup)
            L_PG_BACKUP_TYPE="basebackup"
            ;;
        *)
            write_out "ERROR" "Falta indicar o tipo de backup: [dumpall|basebackup]." | tee -a "${S_ERROR_MSG_FILE}"
            L_EXIT_STATUS_CODE=101
            break            
            ;;
    esac
    
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

    case "${L_PG_BACKUP_TYPE}" in
        basebackup)
            ## Apagar basebackups com mais de L_DAYS_TO_KEEP_BACKUPS dias
            delete_old_files "${S_PG_BASEBACKUP_DIR}" ${L_DAYS_TO_KEEP_BACKUPS}
            L_EXIT_STATUS_CODE=$?
            if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
                break
            fi
            ## Efetuar basebackup
            backup_pgbasebackup "${S_PG_BASEBACKUP_DIR}"
            L_EXIT_STATUS_CODE=$?
            if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
                break
            fi
            ## Apagar ficheiros WAL com mais de L_DAYS_TO_KEEP_BACKUPS se
            ## parametro "-w" tiver sido passado
            if [ ${L_HOUSEKEEPING_WAL_ARCHIVE} -eq 1 ]; then
                delete_old_files "${S_PG_WAL_ARCHIVE_DIR}" ${L_DAYS_TO_KEEP_BACKUPS}
            fi
            L_EXIT_STATUS_CODE=$?
            if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
                break
            fi
            ;;
        dumpall)
            ## Apagar dumpalls com mais de L_DAYS_TO_KEEP_BACKUPS dias
            delete_old_files "${S_PG_DUMPALL_DIR}" ${L_DAYS_TO_KEEP_BACKUPS}
            L_EXIT_STATUS_CODE=$?
            if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
                break
            fi
            ## Efetuar dumpall
            backup_pgdumpall "${S_PG_DUMPALL_DIR}"
            L_EXIT_STATUS_CODE=$?
            if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
                break
            fi
            ## Apagar ficheiros WAL com mais de L_DAYS_TO_KEEP_BACKUPS se
            ## parametro "-w" tiver sido passado
            if [ ${L_HOUSEKEEPING_WAL_ARCHIVE} -eq 1 ]; then
                delete_old_files "${S_PG_WAL_ARCHIVE_DIR}" ${L_DAYS_TO_KEEP_BACKUPS}
            fi
            L_EXIT_STATUS_CODE=$?
            if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
                break
            fi
            ;;
        *)
            write_out "ERROR" "Opcao desconhecida [${L_PG_BACKUP_TYPE}]." | tee -a "${S_ERROR_MSG_FILE}"
            L_EXIT_STATUS_CODE=101
            break
            ;;
    esac    
    
    
    #########################################################################
    ## STOP ACTIONS HERE
    #########################################################################

done

## Verificar se deve enviar alerta
if [ ${L_EXIT_STATUS_CODE} -ne 0 ]; then
    envia_mail
fi
