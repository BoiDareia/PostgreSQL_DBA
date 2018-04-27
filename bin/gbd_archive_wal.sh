#!/usr/bin/bash

## ALTERAR DE ACORDO COM O AMBIENTE
L_PG_CLUSTER="INSTANCIA"
L_RSYNCLOGDIR="/postgresql/${L_PG_CLUSTER}/logs"
L_SCRIPT_NAME="${0##*/}"

## Indicar inicio da execucao
L_ARGS="$@"

## Verificar se temos exatamente 3 argumentos:
## $1 = path of file to archive (%p)
## $2 = file name only          (%f)
## $3 = path of wal archives
if [ $# -ne 3 ]; then
    printf "%s local %s %s postgresql %s : ERROR : %s command needs 3 arguments: wal_file_path wal_filename archive_dir.\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$$" "${L_PG_CLUSTER}" "${L_SCRIPT_NAME}" "${L_SCRIPT_NAME}"
    exit 101
fi

## Verificar se ficheiro WAL ja existe no diretoria de arquivo
if [ -f "$1/$2" ]; then
    printf "%s local %s %s postgresql %s : ERROR : wal %s already exists in %s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$$" "${L_PG_CLUSTER}" "${L_SCRIPT_NAME}" "$2" "$3"
    exit 102
fi

## Copiar wal para diretoria de arquivo, usando rsync (caso seja necessario copiar para local remoto)
# --checksum              skip based on checksum, not mod-time & size
rsync -a --checksum --log-file="${L_RSYNCLOGDIR}/rsync_$(date -u +'%Y-%m').log" "${1}" "$3/$2"

## Verificar sucesso do rsync
if [ ${?} -ne 0 ]; then
    printf "%s local %s %s postgresql %s : ERROR : rsync failed to copy wal %s to %s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$$" "${L_PG_CLUSTER}" "${L_SCRIPT_NAME}" "$2" "$3"
    exit 103
fi
