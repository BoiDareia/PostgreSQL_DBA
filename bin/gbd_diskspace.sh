#!/usr/bin/bash

# Versao 1.0 2014-09-19 Luis Marques
# Versao 1.1 2014-10-21 Luis Marques
# Versao 1.2 2014-10-23 Luis Marques
# Versao 1.3 2015-03-10 Luis Marques
#  - "Limpeza" do codigo  
# Versao 1.4 2017-04-24 Luis Marques
#  - Alteracao dos parametros do comando df para funcionar
#    em linux. Alterar parse do resultado em conformidade  
#  - Adicao de flag para nao enviar sms
#  - Nao tentar processar linhas de configuracao "vazias" 
#    ou comecadas por espaco
#  - Data para os logs em formato ISO 8601 "2017-04-24T06:38:26Z"
# Versao 1.5 2017-12-21 Luis Marques
#  - Alterar para funcionar com bash
#  - Remover especificidades ifx

# O objetivo do script eh utilizar o comando "df" para 
# verificar o espaco ocupado (em termos de percentagem)
# de uma selecao de filesystems.
# A lista de filesystem eh lida de um ficheiro de 
# configuracao, onde eh indicado o filesystem e qual 
# a percentagem de ocupacao que deve ser verificada.
# O script efetua um loop para verificar as entradas
# no ficheiro de configuracao.
# Caso a percentagem tenha sido ultrapassada eh enviado
# alerta atraves de email e/ou/sms com informacao sobre 
# o filesystem em questao.
# O script vai ter 2 niveis de alerta:
# - warning
# - emergency
# O script vai enviar um numero limitado de alertas
# para evitar spam.
# O controlo do envio de alertas vai ser efetuado
# atraves de um ficheiro que contem um contador por
# cada filesystem analisado.
# O ficheiro de contadores tem o seguinte formato:
# - <FILESYSTEM>|<STATUS>|<CONTADOR>
# A logica de controlo eh:
# - Alertas de nivel "warning" incrementam contador ate
#   ao maximo de 3
# - Alertas de nivel "emergency" incrementam o contador 
#   ate ao maximo de 3
# - O contador eh colocado a zero se as condicoes de
#   alerta normalizarem ou mudarem de criticidade
# A informacao a adicionar ao email/sms de alerta eh
# coletada num ficheiro temporario. 


### Parametrizacoes Hardcoded ###
S_BODYFULLPATHNAME="/tmp/gbd_diskspace_messages.tmp"
S_COUNTERFULLPATHNAME="/tmp/gbd_diskspace.counter"
S_TMPCOUNTERFULLPATHNAME="/tmp/gbd_diskspace_counter.tmp"

S_EMAILFROM="posgtres"
S_EMAILTO="dba-postgres@telecom.pt"
S_EMAILCC=""

S_LIMITEENVIOEMAILS=3

# Deve tentar enviar sms. ON=1, OFF=0
S_DEVEENVIARSMS=0

#S_DESTINATARIOSSMS="123456789 987654321"
# Destinatario de sms para debug
S_DESTINATARIOSSMS="123456789"

# Parametros que não devem ser alterados na execucao do script
S_STATUSNORMAL="NORMAL"
S_STATUSWARNING="WARNING"
S_STATUSCRITICAL="CRITICAL"

S_MSGDBG=1
S_MSGNFO=2
S_MSGERR=3

S_NIVELEMERGENCY="EMERGENCY"
S_NIVELWARNING="WARNING"
S_NIVELNOTIFICATION="NOTIFICATION"

# Variavel para controlar output de debug. ON=1, OFF=0
L_MSGSHOWDEBUG=0

# Para imprimir mensagens com formatacao:
# DATA | PID | PRIORIDADE | MENSAGEM
# Uso: printmessage <prioridade> <mensagem>
# prioridade:
#  1 -> NFO (info)
#  2 -> ERR (erro)
#  * -> UNK (desconhecido)
#
# Se a variavel global $L_MSGSHOWDEBUG estiver a 1
# imprime as mensagens de prioridade 1 (DBG)
printmessage()
{
  # Argumentos da funcao: $1, $2
  localPrioridade="$1"
  localMensagem="$2"
  localDate="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  localStrPrioridade="UNK"

  # Determinar a string de prioridade
  case "${localPrioridade}" in
  1)
    # Se houver variavel de debug a 1, escrever mensagem
    if [ "${L_MSGSHOWDEBUG}" -eq 1 ]; then
      localStrPrioridade="DBG"
    else
      # Mensagens de debugs devem ser ignoradas
      return
    fi
    ;;
  2)
    localStrPrioridade="NFO"
    ;;
  3)
    localStrPrioridade="ERR"
    ;;
  *)
    # Nada a fazer,
    ;;
  esac

  printf '%s|%s|%s|%s\n' "${localDate}" "$$" "${localStrPrioridade}" "${localMensagem}"
  return
}


# Imprime instrucoes de utilizacao
# Uso: printhelp <nome script>
printhelp()
{
  printf 'Uso: %s <path para ficheiro de conf>\n' "${1}"
  return
}

# Imprime Bytes com ordens de grandeza
printByteUnits()
{
  # Argumentos da funcao: $1 
  localQuantidadeKiB="$1"
  
  printf "%s" "${localQuantidadeKiB}" | awk 'function human(x) {
    s=" B   KiB MiB GiB TiB EiB PiB YiB ZiB"
    while (x>=1024 && length(s)>1)
  	  {x/=1024; s=substr(s,5)}
    s=substr(s,1,4)
    xf=(s==" B  ")?"%5d   ":"%3.2f"
    return sprintf( xf"%s\n", x, s)
  }
  {gsub(/^[0-9]+/, human($1)); print}'
}


# Envia email pre-formatado com informacao do alerta 
sendalertmail()
{
  # Definir destinatarios e afins
  # enderecos de email separados por ','  
  localFrom="${S_EMAILFROM}"

  localTo="${S_EMAILTO}"
  localCc="${S_EMAILCC}"

  # Ir buscar nome da maquina
  localHost="${L_HOSTNAME}"

  # Formatar data atual 
  localDate="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

  # A criticidade do alerta eh o 1 argumento da funcao
  localLevel="$1"

  # O nome completo do ficheiro com o resto do corpo do email
  # eh o 2 argumento da funcao
  localBodyFile="$2"

  # Usar o sendmail para o envio (opcao -t usa os campos do
  # here document para os enderecos e etc) 
  /usr/sbin/sendmail -t <<EOF
FROM: ${localFrom}
TO: ${localTo}
CC: $localCc
SUBJECT: Host: ${localHost} Event Level: ${localLevel} Event type: Disk Space 

This is an automatic generated mail created by the 
${L_SCRIPTNAME} 
script at host 
${localHost}
------------------------------------------------------------------

Date: ${localDate}
Severity: ${localLevel}

$(cat ${localBodyFile})

------------------------------------------------------------------

EOF

}


# enviar sms com a mensagem de alerta
#  - o primeiro argumento eh a mensagem
#  - o segundo argumento eh a origem (string)
#  - o terceiro argumento eh a lista de numeros de destino,
#    separados por espacos 
ifxenviasms()
{
  if [ ${S_DEVEENVIARSMS} -eq 1 ]; then
    # O fullpathname do binario que envia sms 
    localBinaryFullpath="/usr/bin/scripts/enviasms"
    # Timestamp
    localDate="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    
    # Mensagem
    localMessage="$1"
    
    # Origem do sms (verificar se nao eh vazio ou maior que 11 carateres
    localOrigem="$2"
    # remover espacos em branco
    localOrigem="$(print "${localOrigem}" | tr -d ' ')"
    if [ "${#localOrigem}" -gt 0 ]; then
      localOrigem="$(print "${localOrigem}" | cut -c 1-11)"
    else
      localOrigem="GBD"
    fi
    
    # Numeros destino
    localNumbers="$3"
  
    # Verificar se o binario de envio de sms esta disponivel
    if [ -f "${localBinaryFullpath}" ] && [ -x "${localBinaryFullpath}" ]; then
      # Exportar variavel para o log do binario que envia sms
      export LOG_DIR="/usr/informix/etc"
      # Exportar variavel para a localizacao do certificado
      export ENVIASMS_CFG_DIR="/usr/bin/scripts"
      # para cada numero, enviar sms
      for numero in ${localNumbers}; do
        ## DEBUG ##
        if [ "${L_MSGSHOWDEBUG}" -eq 1 ]; then
          printmessage "${S_MSGDBG}" "sms text:${localMessage}|tmstmp:${localDate}"
        fi
  	  ## porto 5016 para as maquinas de producao
        #printf '%s (%s)\n' "${localMessage}" "${localDate}" | "${localBinaryFullpath}" -alpha -nocheck -h10.251.7.250 -p5016 "${localOrigem}" "${numero}"
        ## porto 5005 para a pbtixs36
        printf '%s (%s)\n' "${localMessage}" "${localDate}" | "${localBinaryFullpath}" -alpha -nocheck -h10.251.7.250 -p5005 "${localOrigem}" "${numero}"
        # Esperar 1 s, para evitar flood para o smsc
        sleep 1
      done
      return 0
    else
      #Nao foi encontrado binario de envio de sms
      printmessage "${S_MSGERR}" "script|${localBinaryFullpath}|O binario para envio de sms nao esta disponivel: ${localBinaryFullpath}"
      return 2
    fi
  else
    ## Nao vai ser enviado sms
    if [ "${L_MSGSHOWDEBUG}" -eq 1 ]; then
      printmessage "${S_MSGDBG}" "sms is disabled|tmstmp:${localDate}"
    fi
    return 1
  fi
}

# Fazer reset do ficheiro (tornar o ficheiro vazio)
# o 1 argumento eh o full pathname do ficheiro  
nullfilecontent()
{
  localFilename="$1"
  cat /dev/null > "${localFilename}"
}

# Ler o valor do ficheiro com o contador
# o 1 argumento eh o full pathname do ficheiro  
readcounterfile()
{
  localFilename="$1"
    
  localCounter=0
  localRead

  if [ -s "${localFilename}" ]; then
    localRead="$(cat "${localFilename}")"
    
    # Se o valor for um numero 
    case "${localRead}" in 
    "([0-9])+")
      localCounter="${localRead}"
    ;;
    esac
#    if [ "${localRead}" = +([0-9]) ]; then
#      localCounter="${localRead}"
#    fi
  fi

  printf '%s' "${localCounter}"
  return 
}


## INICIO CICLO PRINCIPAL ##

L_NUMARGUMENTOS="$#"
L_HOSTNAME="$(hostname)"
L_SCRIPTNAME="$0"

L_NUMFILESYSTEMS=0

# Verificar numero correto de argumentos
case "${L_NUMARGUMENTOS}" in
1)
  FICHEIROCONF="$1"
  printmessage "${S_MSGDBG}" "Vai ser utilizado o ficheiro de config: ${FICHEIROCONF}"
  ;;
*)
  printmessage "${S_MSGERR}" "script|Numero incorreto de argumentos"
  printhelp "$0"
  exit 1
  ;;
esac

# Verificar se o ficheiro de config indicado existe
if [ -f "${FICHEIROCONF}" ]; then
  printmessage "${S_MSGDBG}" "Foi encontrado o ficheiro de config: ${FICHEIROCONF}"
else
  printmessage "${S_MSGERR}" "script|Nao foi encontrado o ficheiro de config: ${FICHEIROCONF}"
  printhelp
  exit 1
fi

printmessage "${S_MSGDBG}" "Analise de filesystems"

# Para cada linha do ficheiro de configuração, ler 3 parametros
# FILESYSTEM | PERCENTAGEM AVISO | PERCENTAGEM CRITICO
# Usar o "|" como separador
while IFS="|" read -r linha warning critical lixo; do
  # Verificar se linha inicia por #
  comentarioPattern='#*'
  # Verificar se linha inicia por espaco
  espacoPattern=' *'
  # Verificar se linha vazia
  vaziaPattern=''
  
  case "${linha}" in
  ${comentarioPattern} | ${espacoPattern} |  ${vaziaPattern})
    printmessage "${S_MSGDBG}" "Esta linha de configuracao foi ignorada: ${linha}"
    ;;
  *) 
    printmessage "${S_MSGDBG}" "Verificar espaco ocupado no filesystem: ${linha}"
    # Colocar num array o resultado do df.
    # O array vai ter numero de elmentos igual as palavras do df,
    # separadas por espacos, mundanca de linha, etc.
    linhaResultado="$(df -kP "${linha}")"
    # o numero esperado de palavras eh 13 (2 linhas)
    numPalavrasResultado="$(printf '%s\n' "${linhaResultado}" | wc -w)"
    if [ "${numPalavrasResultado}" -ne 13 ]; then
      dfFailMessage="O comando df para o filesystem ${linha} nao devolveu o resultado esperado"
      printmessage "${S_MSGERR}" "script|${dfFailMessage}"
      printmessage "${S_MSGNFO}" "script|Numero palavras do df: ${numPalavrasResultado}"
      printmessage "${S_MSGNFO}" "script|${linhaResultado}"
      # Enviar email a indicar falha do comando df
      # Preencher arrays com as 4 colunas
      ARRAYFILESYSTEMS["${L_NUMFILESYSTEMS}"]="${linha}"
      ARRAYSTATUSFS["${L_NUMFILESYSTEMS}"]="${S_STATUSWARNING}"
      ARRAYMESSAGEFS["${L_NUMFILESYSTEMS}"]="${dfFailMessage}"
      ARRAYFREESPACEFS["${L_NUMFILESYSTEMS}"]=-1
    else
      # transformar a linha num array de palavras
      # O index do array comeca em zero
      arrayResultado=(${linhaResultado})
      
      # Preencher arrays com as 4 colunas
      ARRAYFILESYSTEMS["${L_NUMFILESYSTEMS}"]="${linha}"
      ARRAYUSEDSPACEFS["${L_NUMFILESYSTEMS}"]="${arrayResultado[9]}"
      ARRAYFREESPACEFS["${L_NUMFILESYSTEMS}"]="${arrayResultado[10]}"

      # O valor de percentagem de espaco ocupado esta na posicao 11
      # Verificar se o espaco ocupado esta acima do critico
      # ${parameter%word} removes the shortest suffix pattern matching word
      if [ "${arrayResultado[11]%?}" -gt "${critical}" ]; then
        localFreeSpace="$(printByteUnits $(( arrayResultado[10] * 1024 )))"
        localMessage="filesystem|${linha}|${critical}|${arrayResultado[11]%?}|$(( arrayResultado[10] * 1024 ))|${linha} com ocupacao de ${arrayResultado[11]%?} % ( CRITICO > ${critical} % ), ${localFreeSpace} livres"
        printmessage "${S_MSGERR}" "${localMessage}"
        # Incrementar o contador de alarmes criticos
        # Preencher arrays com as 4 colunas
        ARRAYSTATUSFS["${L_NUMFILESYSTEMS}"]="${S_STATUSCRITICAL}"

      # Verificar se o espaco ocupado esta acima do aviso
      # ${parameter%word} removes the shortest suffix pattern matching word
      elif [ "${arrayResultado[11]%?}" -gt "${warning}" ]; then
        localFreeSpace="$(printByteUnits $(( arrayResultado[10] * 1024 )))"
        localMessage="filesystem|${linha}|${critical}|${arrayResultado[11]%?}|$((arrayResultado[10] * 1024))|${linha} com ocupacao de ${arrayResultado[11]%?} % ( AVISO > ${warning} % ), ${localFreeSpace} livres"
        printmessage "${S_MSGERR}" "${localMessage}"
        # Incrementar o contador de alarmes aviso
        # Preencher arrays com as 4 colunas
        ARRAYSTATUSFS["${L_NUMFILESYSTEMS}"]="${S_STATUSWARNING}"
      else
        localFreeSpace="$(printByteUnits $(( arrayResultado[10] *1024 )))"
        localMessage="filesystem|${linha}|${critical}|${arrayResultado[11]%?}|$(( arrayResultado[10] *1024 ))|${linha} com ocupacao de ${arrayResultado[11]%?} % ( <= ${warning} % ), ${localFreeSpace} livres"
        printmessage "${S_MSGNFO}" "${localMessage}"
        
        # Preencher arrays com as 4 colunas
        ARRAYSTATUSFS["${L_NUMFILESYSTEMS}"]="${S_STATUSNORMAL}"
      fi
      ARRAYMESSAGEFS["${L_NUMFILESYSTEMS}"]="${localMessage}"
    fi
    
    # Incrementar o numero de filesystems verificados
    (( L_NUMFILESYSTEMS=L_NUMFILESYSTEMS+1 )) 
    printmessage "${S_MSGDBG}" "Iteracao numero: ${L_NUMFILESYSTEMS}"
    ;;
  esac
done < "${FICHEIROCONF}"

## DEBUG ##
if [ "${L_MSGSHOWDEBUG}" -eq 1 ]; then
  i=0
  while [ "${i}" -lt "${L_NUMFILESYSTEMS}" ]; do
    printmessage "${S_MSGDBG}" "Filesystem|${ARRAYFILESYSTEMS[${i}]}"
    printmessage "${S_MSGDBG}" "status|${ARRAYSTATUSFS[${i}]}"
    printmessage "${S_MSGDBG}" "message|${ARRAYMESSAGEFS[${i}]}"
    (( i = i + 1 ))
  done
fi

## ENVIO DE ALERTAS ##
printmessage "${S_MSGDBG}" "Envio de alertas"
# Limpar ficheiro de trabalho (novo ficheiro de contadores)
nullfilecontent "${S_TMPCOUNTERFULLPATHNAME}"
# Limpar ficheiro de trabalho (email body) 
nullfilecontent "${S_BODYFULLPATHNAME}"

# Para cada filesystem analisado, verificar o envio de alertas
i=0
while [ "${i}" -lt "${L_NUMFILESYSTEMS}" ]; do
  # Valores por defeito para filesystem analisado
  STATUSALERTAANTERIOR="${S_STATUSNORMAL}"
  NUMALERTASSENVIADOS=0
  
  # Verificar se o ficheiro de contadores existe
  if [ -f "${S_COUNTERFULLPATHNAME}" ]; then
    printmessage "${S_MSGDBG}" "Foi encontrado ficheiro de contadores"
    # Verificar se o ficheiro de contadores ja tem entrada correspondente
    # Para cada linha do ficheiro de contadores, ler 3 parametros
    # <FILESYSTEM>|<STATUS>|<NUN ALERTAS ENVIADOS>
    # Usar o "|" como separador
    while IFS="|" read -r localfs statusfs numalerts lixo; do
      case "${localfs}" in
      "${ARRAYFILESYSTEMS[${i}]}")
        STATUSALERTAANTERIOR="${statusfs}"
        NUMALERTASSENVIADOS="${numalerts}"
        ;;
      *)
        # Nao foi encontrado contador anterior
        printmessage "${S_MSGDBG}" "Nao foi encontrado contador para ${ARRAYFILESYSTEMS[${i}]}"
        ;;
      esac
    done < "${S_COUNTERFULLPATHNAME}"      
  fi
  ## DEBUG ##
  if [ "${L_MSGSHOWDEBUG}" -eq 1 ]; then
    printmessage "${S_MSGDBG}" "Filesystem:${ARRAYFILESYSTEMS[${i}]}|status:${STATUSALERTAANTERIOR}|envios:${NUMALERTASSENVIADOS}"
  fi
  
  # Logica para decidir o envio de alertas e atualizacao dos contadores (matriz 3x3)
  # Para o status atual decidir se deve haver envio de alerta
  
  # Caso status atual ser "Critical"
  case "${ARRAYSTATUSFS[${i}]}" in
  "${S_STATUSCRITICAL}")
    case "${STATUSALERTAANTERIOR}" in
    "${S_STATUSCRITICAL}")
      # Nao houve alteracao do status, verificar o envio de alerta
      if [ "${NUMALERTASSENVIADOS}" -lt "${S_LIMITEENVIOEMAILS}" ]; then
        # Ainda nao foi atingido o limite de alertas
        (( NUMALERTASSENVIADOS = NUMALERTASSENVIADOS + 1 ))
        # Escrever mensagem do email para ficheiro (codigo antigo)
        printf '\n%s\n' "${ARRAYMESSAGEFS[${i}]}" > "${S_BODYFULLPATHNAME}"
        # Enviar alerta
        STRINGNIVEL="${S_NIVELEMERGENCY}"
        sendalertmail "${STRINGNIVEL}" "${S_BODYFULLPATHNAME}"
        printmessage "${S_MSGNFO}" "script|Enviado email(#${NUMALERTASSENVIADOS}) com criticidade ${STRINGNIVEL} para ${ARRAYFILESYSTEMS[${i}]}"
        localSmsMessage="Disk Space ${STRINGNIVEL} @ ${L_HOSTNAME} : ${ARRAYUSEDSPACEFS[${i}]} % : ${ARRAYFILESYSTEMS[${i}]} - $(printByteUnits $(( ${ARRAYFREESPACEFS[${i}]} * 1024 ))) livres"
        ifxenviasms "${localSmsMessage}" "${L_HOSTNAME}" "${S_DESTINATARIOSSMS}"
        # Verificar se o enviasms nao devolveu exit code com erro (diferente de zero)
        if [ $? -eq 0 ]; then
          printmessage "${S_MSGNFO}" "script|Enviado sms(#${NUMALERTASSENVIADOS}) com criticidade ${STRINGNIVEL} para ${ARRAYFILESYSTEMS[${i}]}"
        fi
      else
        # Ja foi enviado o numero maximo de alertas
        printmessage "${S_MSGNFO}" "script|Limite de envio de alertas atingido ( $((${S_LIMITEENVIOEMAILS})) ) para ${ARRAYFILESYSTEMS[${i}]}"
      fi
      # Escrever contador atualizado para novo ficheiro de contadores
      printf '%s|%s|%s\n' "${ARRAYFILESYSTEMS[${i}]}" "${ARRAYSTATUSFS[${i}]}" "${NUMALERTASSENVIADOS}" >> "${S_TMPCOUNTERFULLPATHNAME}"
      ;;
    "${S_STATUSWARNING}" | "${S_STATUSNORMAL}")
      # Mudou status para critical, efetuar reset do contador e enviar alerta
      NUMALERTASSENVIADOS=1
      # Escrever mensagem do email para ficheiro (codigo antigo)
      printf '\n%s\n' "${ARRAYMESSAGEFS[${i}]}" > "${S_BODYFULLPATHNAME}"
      # Enviar alerta
      STRINGNIVEL="${S_NIVELEMERGENCY}"
      sendalertmail "${STRINGNIVEL}" "${S_BODYFULLPATHNAME}"
      printmessage "${S_MSGNFO}" "script|Enviado email(#${NUMALERTASSENVIADOS}) com criticidade ${STRINGNIVEL} para ${ARRAYFILESYSTEMS[${i}]}"
      localSmsMessage="Disk Space ${STRINGNIVEL} @ ${L_HOSTNAME} : ${ARRAYUSEDSPACEFS[${i}]} % : ${ARRAYFILESYSTEMS[${i}]} - $(printByteUnits $(( ${ARRAYFREESPACEFS[${i}]} * 1024 ))) livres"
      ifxenviasms "${localSmsMessage}" "${L_HOSTNAME}" "${S_DESTINATARIOSSMS}"
      # Verificar se o enviasms nao devolveu exit code com erro (diferente de zero)
      if [ $? -eq 0 ]; then
        printmessage "$S_MSGNFO" "script|Enviado sms(#$NUMALERTASSENVIADOS) com criticidade $STRINGNIVEL para ${ARRAYFILESYSTEMS[$i]}"
      fi
      # Escrever contador atualizado para novo ficheiro de contadores
      printf '%s|%s|%s\n' "${ARRAYFILESYSTEMS[${i}]}" "${ARRAYSTATUSFS[${i}]}" "${NUMALERTASSENVIADOS}" >> "${S_TMPCOUNTERFULLPATHNAME}"
      ;;
    *)
      # Codigo de status invalido, produzir output indicativo
      printmessage "${S_MSGERR}" "filesystem|${ARRAYFILESYSTEMS[${i}]}|Filesystem ${ARRAYFILESYSTEMS[${i}]} com status anterior invalido: ${STATUSALERTAANTERIOR}"
      ;;
    esac
    ;;
  # Caso status atual ser "Warning"
  "${S_STATUSWARNING}")
    case "${STATUSALERTAANTERIOR}" in
    "${S_STATUSCRITICAL}" | "${S_STATUSNORMAL}")
      # Mudou status para warning, efetuar reset do contador e enviar alerta
      NUMALERTASSENVIADOS=1
      # Escrever mensagem do email para ficheiro (codigo antigo)
      printf '\n%s\n' "${ARRAYMESSAGEFS[${i}]}" > "${S_BODYFULLPATHNAME}"
      # Enviar alerta
      STRINGNIVEL="${S_NIVELWARNING}"
      sendalertmail "${STRINGNIVEL}" "${S_BODYFULLPATHNAME}"
      printmessage "${S_MSGNFO}" "script|Enviado email(#${NUMALERTASSENVIADOS}) com criticidade ${STRINGNIVEL} ${ARRAYFILESYSTEMS[${i}]}"
      localSmsMessage="Disk Space ${STRINGNIVEL} @ ${L_HOSTNAME} : ${ARRAYUSEDSPACEFS[${i}]} % : ${ARRAYFILESYSTEMS[${i}]} - $(printByteUnits $(( ${ARRAYFREESPACEFS[${i}]} * 1024 ))) livres"
      ifxenviasms "${localSmsMessage}" "${L_HOSTNAME}" "${S_DESTINATARIOSSMS}"
      # Verificar se o enviasms nao devolveu exit code com erro (diferente de zero)
      if [ $? -eq 0 ]; then
        printmessage "${S_MSGNFO}" "script|Enviado sms(#${NUMALERTASSENVIADOS}) com criticidade ${STRINGNIVEL} para ${ARRAYFILESYSTEMS[${i}]}"
      fi
      # Escrever contador atualizado para novo ficheiro de contadores
      printf '%s|%s|%s\n' "${ARRAYFILESYSTEMS[${i}]}" "${ARRAYSTATUSFS[${i}]}" "${NUMALERTASSENVIADOS}" >> "${S_TMPCOUNTERFULLPATHNAME}"
      ;;
    "${S_STATUSWARNING}")
      # Nao houve alteracao do status, verificar o envio de alerta
      if [ "${NUMALERTASSENVIADOS}" -lt "${S_LIMITEENVIOEMAILS}" ]; then
        # Ainda nao foi atingido o limite de alertas
        (( NUMALERTASSENVIADOS = NUMALERTASSENVIADOS + 1 ))
        # Escrever mensagem do email para ficheiro (codigo antigo)
        printf '\n%s\n' "${ARRAYMESSAGEFS[${i}]}" > "${S_BODYFULLPATHNAME}"
        # Enviar alerta
        STRINGNIVEL="${S_NIVELWARNING}"
        sendalertmail "${STRINGNIVEL}" "${S_BODYFULLPATHNAME}"
        printmessage "${S_MSGNFO}" "script|Enviado email(#${NUMALERTASSENVIADOS}) com criticidade ${STRINGNIVEL} para ${ARRAYFILESYSTEMS[${i}]}"
        localSmsMessage="Disk Space ${STRINGNIVEL} @ ${L_HOSTNAME} : ${ARRAYUSEDSPACEFS[${i}]} % : ${ARRAYFILESYSTEMS[${i}]} - $(printByteUnits $(( ${ARRAYFREESPACEFS[${i}]} * 1024 ))) livres"
        ifxenviasms "${localSmsMessage}" "${L_HOSTNAME}" "${S_DESTINATARIOSSMS}"
        # Verificar se o enviasms nao devolveu exit code com erro (diferente de zero)
        if [ $? -eq 0 ]; then
          printmessage "${S_MSGNFO}" "script|Enviado sms(#${NUMALERTASSENVIADOS}) com criticidade ${STRINGNIVEL} para ${ARRAYFILESYSTEMS[${i}]}"
        fi
      else
        # Ja foi enviado o numero maximo de alertas
        printmessage "${S_MSGNFO}" "script|Limite de envio de alertas atingido ( $((${S_LIMITEENVIOEMAILS})) ) para ${ARRAYFILESYSTEMS[${i}]}"
      fi
      # Escrever contador atualizado para novo ficheiro de contadores
      printf '%s|%s|%s\n' "${ARRAYFILESYSTEMS[${i}]}" "${ARRAYSTATUSFS[${i}]}" "${NUMALERTASSENVIADOS}" >> "${S_TMPCOUNTERFULLPATHNAME}"
      ;;
    *)
      # Codigo de status invalido, produzir output indicativo
      printmessage "${S_MSGERR}" "filesystem|${ARRAYFILESYSTEMS[${i}]}|Filesystem ${ARRAYFILESYSTEMS[${i}]} com status anterior invalido: ${STATUSALERTAANTERIOR}"
      ;;
    esac
    ;;
  # Caso status atual eh "Normal"
  "${S_STATUSNORMAL}")
    case "${STATUSALERTAANTERIOR}" in
    "${S_STATUSCRITICAL}" | "${S_STATUSWARNING}")
      # Mudou status para normal, efetuar envio de normalizacao
      # Escrever mensagem do email para ficheiro (codigo antigo)
      printf '\n%s\n' "Filesystem: ocupacao normalizada" > "${S_BODYFULLPATHNAME}"
      printf '\n%s\n' "${ARRAYMESSAGEFS[${i}]}" >> "${S_BODYFULLPATHNAME}"
      # Enviar alerta
      STRINGNIVEL="${S_NIVELNOTIFICATION}"
      sendalertmail "${STRINGNIVEL}" "${S_BODYFULLPATHNAME}"
      printmessage "${S_MSGNFO}" "script|Enviado email com notificacao de ocupacao de filesystem normalizado para ${ARRAYFILESYSTEMS[${i}]}"
      localSmsMessage="Disk Space ${STRINGNIVEL} @ ${L_HOSTNAME} : ${ARRAYUSEDSPACEFS[${i}]} % : ${ARRAYFILESYSTEMS[${i}]} - $(printByteUnits $(( ${ARRAYFREESPACEFS[${i}]} * 1024 ))) livres"
      ifxenviasms "${localSmsMessage}" "${L_HOSTNAME}" "${S_DESTINATARIOSSMS}"
      if [ ${?} -eq 0 ]; then
        printmessage "${S_MSGNFO}" "script|Enviado sms com notificacao de normalizacao para ${ARRAYFILESYSTEMS[${i}]}"      
      fi
      # Filesystem normalizou, nao eh necessario escrever contador
      ;;
    "${S_STATUSNORMAL}")
      printmessage "${S_MSGDBG}" "filesystem|${ARRAYFILESYSTEMS[${i}]}|Filesystem ${ARRAYFILESYSTEMS[${i}]} com ocupacao normalizada"
      ;;
    *)
      # Codigo de status invalido, produzir output indicativo
      printmessage "${S_MSGERR}" "filesystem|${ARRAYFILESYSTEMS[${i}]}|Filesystem ${ARRAYFILESYSTEMS[${i}]} com status anterior invalido: ${STATUSALERTAANTERIOR}"
      ;;
    esac
    ;;
  *)
    # Codigo de status invalido, produzir output indicativo
    printmessage "${S_MSGERR}" "filesystem|${ARRAYFILESYSTEMS[${i}]}|Filesystem ${ARRAYFILESYSTEMS[${i}]} com status atual invalido: ${ARRAYSTATUSFS[${i}]}"
    ;;
  esac
  (( i = i + 1 ))
done

# Copiar novo ficheiro de contadores, se tiver entradas
# ( -s : ficheiro existe e tem tamanho maior que zero)
if [ -s "${S_TMPCOUNTERFULLPATHNAME}" ]; then
  cp "${S_TMPCOUNTERFULLPATHNAME}" "${S_COUNTERFULLPATHNAME}"
# nao existem contadores, apagar ficheiro de contadores anterior, se existir
# ( -f : ficheiro existe e eh um ficheiro normal )
elif [ -f "${S_COUNTERFULLPATHNAME}" ]; then
  rm "${S_COUNTERFULLPATHNAME}"
fi

# Limpar o ficheiro de trabalho
rm "${S_BODYFULLPATHNAME}"
rm "${S_TMPCOUNTERFULLPATHNAME}"
