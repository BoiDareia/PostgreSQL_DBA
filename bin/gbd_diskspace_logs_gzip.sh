#!/usr/bin/bash
#
# DESCRIPTION: comprimir os ficheiros de log com mais de x dias
#
# DATE: 2015-03
# DATE: 2017-12-16 Luis Marques
#  - Alterar para executar com bash


### CONFIGURACAO ###
#DIAS=60
S_DIASAGUARDAR=60
S_DIRETORIOLOGS="/postgresql/INSTANCIA/logs"
S_FILTRO='gbd_diskspace_????-??.log'

### FUNCOES ###

# Para imprimir mensagens com formatacao:
# DATA | PRIORIDADE | MENSAGEM
# Uso: printmessage <prioridade> <mensagem>
# prioridade:
#  1 -> NFO (info)
#  2 -> ERR (erro)
#  * -> UNK (desconhecido)
printmessage()
{
    localPrioridade=$1
    localMensagem=$2
    localDate=$(date -u +'%Y-%m-%d %H:%M:%SZ')
    localStrPrioridade="UNK"

    # Determinar a string de prioridade
    case ${localPrioridade} in
    1)
        localStrPrioridade="NFO"
        ;;
    2)
        localStrPrioridade="ERR"
        ;;
    *)
        # Nada a fazer,
        ;;
    esac

    printf '%s|%s|%s|%s\n' "${localDate}" "$$" "${localStrPrioridade}" "${localMensagem}"
    return
}


### MAIN ###

# Verificar se o diretorio existe e eh acessivel
if [ -d "${S_DIRETORIOLOGS}" ] && [ -x "${S_DIRETORIOLOGS}" ]; then
	# Para cada ficheiro no filtro, verificar timestamp
	for ficheiro in $(ls -tr ${S_DIRETORIOLOGS}/${S_FILTRO}); do
		if [ $(find $ficheiro -mtime +${S_DIASAGUARDAR} | wc -l) -eq 0 ]; then
			# Ficheiro foi modificado ah menos de S_DIASAGUARDAR dias
			#printmessage 1 "Ignorar: $ficheiro"
			break;
		else
			# Ficheiro foi modificad ah mais de S_DIASAGUARDAR dias
			# efetuar compressao
			L_RESULTADO=$(/usr/bin/gzip -v "${ficheiro}" 2>&1)
			printmessage 1 "Comprimir: ${L_RESULTADO}"
		fi
	done
fi

