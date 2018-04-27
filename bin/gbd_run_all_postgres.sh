#!/bin/bash
#############################################################################
# Executar para todas as instancias configuradas pelos scripts setpg e envpg
# o comandoindicado
#############################################################################



#S_PATH_PREFIX="/postgresql/basedir"
S_PATH_PREFIX="/usr/postgres"

# source do envpg
. "${S_PATH_PREFIX}/bin/envpg"


printf "%s [%s] INFO : Inicio da execucao do script [%s]\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$$" "$0"
printf "%s [%s] INFO : Comando a executar [%s]\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$$" "$@"

# Para cada valor devolvido por "get_pg_admin_id_list", mudar para o respetivo ambiente
# e efetuar o backup. Pode ser substituido por uma lista "manual"
for I_INSTANCE in $(get_pg_admin_id_list); do

    # "Mudar" para o ambiente, redirecionando output evitar as mensagens
    . "${S_PATH_PREFIX}/bin/setpg" ${I_INSTANCE} 1> /dev/null
    printf "%s [%s] INFO : Instancia [${PGCLUSTER}], Opcao [${I_INSTANCE}]\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$$"
    # Executar o comando
    $@
    done

printf "%s [%s] INFO : Fim da execucao do script [$0]\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$$"

