#!/usr/bin/bash
#############################################################################
# Script para verificar e preparar a execucao dos scripts gbd (crontab).
# Vai testar se a diretoria de scripts existe (por causa de cluster SO,
# provavelmente redundante, visto os scripts nao estarem presentes se 
# os FS nao estiverem montados). 
# Vai adicionar ao PATH a diretoria de scrips (por causa do crontab)
# (teste simplistico para verificar se eh o no ativo)

# Assuminos que o crontab tem /postgresql/basedir/bin adicionado ao PATH
GBD_PGBIN_DIR="/postgresql/basedir/bin"
# run parameters only if GBD_PGBIN_DIR exists

if [ -d "${GBD_PGBIN_DIR}" ]; then
    ## Colocar o ambiente PostgreSQL correto
    export GBD_SILENT_SETPG=1  ## menos output por parte do setpg
    . setpg 1
    ## Execute parameters
    $*
fi
