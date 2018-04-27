#!/usr/bin/bash

# Versao 1.0 2014-09-19 Luis Marques
# Versao 1.1 2015-03-11 Luis Marques
#  - "Limpeza" do codigo
# Versao 1.2 2015-12-21 Luis Marques
#  - Alterar para funcionar com bash

# Este script efetua o "reset" (apaga o ficheiro)
# do contador de envio de alertas do gbd_diskspace 

COUNTERFULLPATHNAME="/tmp/gbd_diskspace.counter"

if [ -a "${COUNTERFULLPATHNAME}" ]; then
  rm "${COUNTERFULLPATHNAME}"
  printf '%s|%s|NFO|Removed file %s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" "$$" "${COUNTERFULLPATHNAME}" 
fi
