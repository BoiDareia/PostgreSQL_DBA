#!/usr/bin/bash
#
#  Filename: monitor_hotstandby
#  Usage is $0 -m master:port -s slave:port -b <PostgreSQL Bin Directory>
#  Author: Sergio Goncalves
#  Date: 7 Fev 2018
#
#  Exit codes
#  101 - Erro nas opcoes de linha de comando
#  102 - Nao foi encontrado o binario psql
#  103 - Master nao respondeu ao "ping"
#  104 - Slave nao respondeu ao "ping"
#  105 - Slave nao esta em recovery mode
#  106 - Slave esta atrasado em relacao ao Master
#

S_PROGNAME="${0##*/}"

L_MAX_DIFF=0

while getopts "m:s:b:n:" opt; do
    case ${opt} in
        m)
            L_HOSTNAME_MASTER=$(echo ${OPTARG} | cut -d":" -f1)
            L_PORT_MASTER=$(echo ${OPTARG} | cut -d":" -f2)
            ;;
        s)
            L_HOSTNAME_SLAVE=$(echo ${OPTARG} | cut -d":" -f1)
            L_PORT_SLAVE=$(echo ${OPTARG} | cut -d":" -f2)
            ;;
        b) 
            L_PGHOME="${OPTARG}"
            ;;
        n)
            L_MAX_DIFF=${OPTARG}
            ;;
    esac
done
PSQL=${L_PGHOME}/psql

function check_options_usage()
{
    L_MENSAGEM_AJUDA="${S_PROGNAME} -m master:port -s slave:port -b <pg bin directory> -n <max diff for logs>"
    if [ -z "${L_HOSTNAME_MASTER}" ]; then
        printf "USAGE:\n"
        printf "${L_MENSAGEM_AJUDA}\n"
        exit 101
    fi
    if [ -z "${L_HOSTNAME_SLAVE}" ]; then
        printf "USAGE:\n"
        printf "${L_MENSAGEM_AJUDA}\n"
        exit 101
    fi
    if [ -z "${L_PORT_MASTER}" ]; then
        printf "USAGE:\n"
        printf "${L_MENSAGEM_AJUDA}\n"
        exit 101
    fi
    if [ -z "${L_PORT_SLAVE}" ]; then
        printf "USAGE:\n"
        printf "${L_MENSAGEM_AJUDA}\n"
        exit 101
    fi
    if [ -z "${L_PGHOME}" ]; then
        printf "USAGE:\n"
        printf "${L_MENSAGEM_AJUDA}\n"
        exit 101
    fi
    if [ -z "${L_MAX_DIFF}" ]; then
        printf "USAGE:\n"
        printf "${L_MENSAGEM_AJUDA}\n"
        exit 101
    fi
}

## Verifica conexao do Master e Slave
function verifybin_connect()
{
    if [ ! -f "${L_PGHOME}/psql" ]; then
        printf "ERROR: psql Not Found!\n"
        exit 102
    fi
    S_QUERY_STRING_PING="SELECT 'ping';"
    ${L_PGHOME}/psql -h $1 -p $2 -c "${S_QUERY_STRING_PING}" >/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        printf "ERROR: O Master nao responde em ${L_HOSTNAME_MASTER}\n"
        exit 103
    fi
    ${L_PGHOME}/psql -h $3 -p $4 -c "${S_QUERY_STRING_PING}" >/dev/null 2>/dev/null
    if [ $? -ne 0 ]; then
        printf "ERROR: O Slave nao responde em ${L_HOSTNAME_SLAVE}\n"
        exit 104
    fi
}

## Verifica estado de recovery
function verify_is_recovery()
{
    S_QUERY_STRING_RECOVERY="SELECT pg_is_in_recovery()::INT;"
    L_RECOVERY_STATUS=$($L_PGHOME/psql -c "${S_QUERY_STRING_RECOVERY}" -t -h $1 -p $2 template1 | sed '/^$/d')
    if [ ${L_RECOVERY_STATUS} -eq 1 ]; then
        printf "INFO: PG esta em Recovery Mode\n"
    else
        printf "ERROR: O Slave nao esta em Recovery Mode\n"
        exit 105
    fi
}

## Converte para decimal
function convert_decimal()
{
    L_DECIMAL_VAL=$(echo "ibase=16;obase=A;$1" | bc)
    printf "${L_DECIMAL_VAL}\n"
}

## Converte o transaction log location de string para file name
function get_xlog_name()
{
    S_QUERY_STRING_XLOG_NAME="SELECT pg_xlogfile_name('$1');"
    L_XLOGNAME=$($PSQL -h $2 -p $3 -t -c "${S_QUERY_STRING_XLOG_NAME}" template1 | sed '/^$/d')
    printf "${L_XLOGNAME}\n"
}

## Bloco principal
function main()
{
    verifybin_connect $1 $2 $3 $4
    verify_is_recovery $3 $4
    
    S_QUERY_STRING_XLOG_LOCATION="SELECT pg_current_xlog_location();"
    S_QUERY_STRING_XLOG_RECEIVE="SELECT pg_last_xlog_receive_location();"
    L_XLOG_MASTER=$($PSQL -t -c "${S_QUERY_STRING_XLOG_LOCATION}" -h $1 -p $2 template1 | sed '/^$/d')
    L_XLOG_SLAVE=$($PSQL -t -c "${S_QUERY_STRING_XLOG_RECEIVE}" -h $3 -p $4 template1 | sed '/^$/d')
    
    L_WAL_NAME_SLAVE=$(get_xlog_name ${L_XLOG_SLAVE} $1 $2)
    L_WAL_NAME_MASTER=$(get_xlog_name ${L_XLOG_MASTER} $1 $2)
    L_XLOG_LOCATION_MASTER=$(convert_decimal "${L_WAL_NAME_MASTER}")
    L_XLOG_LOCATION_SLAVE=$(convert_decimal "${L_WAL_NAME_SLAVE}")
    L_XLOG_DIFF=$(echo "${L_XLOG_LOCATION_MASTER} - ${L_XLOG_LOCATION_SLAVE}" | bc)
    
    if [ ${L_XLOG_DIFF} -gt ${L_MAX_DIFF} ]; then
        printf "WARNING: O Slave esta atrasado em ${L_XLOG_DIFF} ficheiros\n"
        exit 106
    else
        printf "A replicacao entre ${L_HOSTNAME_MASTER} -> ${L_HOSTNAME_SLAVE} esta sincronizada\n"
        exit 0
    fi
}

check_options_usage
main ${L_HOSTNAME_MASTER} ${L_PORT_MASTER} ${L_HOSTNAME_SLAVE} ${L_PORT_SLAVE}


