#!/bin/bash

GOTIFY_PRIORITY=5

print_help() {
  echo "Docker backup tool"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Usage examples:"
  echo "       $0 --help"
  echo "       $0 --template" 
  echo "       $0 --backup /home/user/backup_config.json" 
  echo ""
  echo "Options:"
  echo "  -h, --help"
  echo "         print this help and exit"
  echo ""
  echo "  -t, --template"
  echo "         print a backup config template structure with locally found docker containers"
  echo ""
  echo "  -b config, --backup config"
  echo "         perform backup with configuration"
}

container_infos=""

get_container_infos() {
  # container_infos="{["
  container_infos=$(sudo  docker container ls --format '{{json}}')
  # container_infos="${container_infos}]}"
  
  echo ${container_infos}
}

create_backup_config_template() {
  date_str=$(date +"%Y-%m-%d %H:%M:%S")
  echo "DATE_STR: ${date_str}"
  
  template_str=$(sudo docker container ls  --format '{"name": "{{.Names}}", "id": "{{.ID}}", "image": "{{.Image}}", "state": "{{.State}}", "storage_dir": ""}' | jq -s --arg d "${date_str}" '{created: $d, backup_base_dir: "", backup_items: ., notification: {type: "gotify", url: "", token: ""} }')

  echo "${template_str}" > $1
}

OPTSTRING=":t:b:h"

while getopts "${OPTSTRING}" opt; do
  case "${opt}" in
    t)
      echo "generating template to file '${OPTARG}'"
      create_backup_config_template ${OPTARG}
      exit 0
      ;;
    b)
      echo "starting backup, config file: '${OPTARG}'"
      cfile="${OPTARG}"
      ;;
    h | *)
      print_help
      exit 0
      ;;
  esac
done

backup_config_file=${cfile}

if [ ! -f "${backup_config_file}" ]; then
  echo "ERROR: configuration '${backup_config_file}' does not exist. Exit."
  exit 2
fi

backup_base_dir=$(jq '.backup_base_dir' ${backup_config_file} | sed -s 's/\"//g')

if [ ! -d "${backup_base_dir}" ]; then
  echo "ERROR: backup base dir '${backup_base_dir}' does not exist! Exit."
  exit 2
fi

backup_dir=${backup_base_dir}/`date +"%Y-%m-%d"` 
notification="starting backup: "

mkdir -p ${backup_dir}

if [ ! -d "${backup_dir}" ]; then
  echo "ERROR: backup dir '${backup_dir}' does not exist! Exit."
  exit 2
fi


echo "creating backups in '${backup_dir}' ..."

current_datetime=$(date +"%Y%m%dT%H%M%S")

add_n() {
  notification="${notification} $1"
}

get_container_id()  {
  cid=$(sudo docker ps --filter "NAME=$1" --format json | jq '. | .ID' | sed -s 's/\"//g')
  echo "+++ container ID of $1: $cid"
}

stop_container() {
  echo "+++ stopping container with ID $1 ..."
  sudo docker stop $1
}

start_container() {
  echo "+++ starting container with ID $1 ..."
  sudo docker start $1
}

backup_volumes() {
  echo "+++ backing up volumes for $1 ..."
  backup_filename="$1_${current_datetime}_backup.tar"
  backup_fullpath="${backup_dir}/${backup_filename}"
  tar --exclude='*.log' -cpf "${backup_fullpath}" "$2"
  echo "++ TAR contents:"
  tar -tf "${backup_fullpath}"
  gzip "${backup_fullpath}" # &
  # rm  "${backup_fullpath}"
}

do_backup() {
#  echo "========================================================"
#  echo ""
#  echo ">> processing $1."
#  echo ""

  get_container_id "$1"
  stop_container $cid
  backup_volumes "$1" "$2"
  start_container $cid
}

backup_all() {
#  echo ">>> config file: '${backup_config_file}'"
  add_n "using backup dir '${backup_dir}', containers ["

  readarray carr < <(jq '.backup_items[] | .name'        ${backup_config_file})
  readarray sarr < <(jq '.backup_items[] | .storage_dir' ${backup_config_file})

  for idx in $(seq 0 $((${#carr[@]}-1))); do
    cname=$(echo ${carr[$idx]} | sed -s 's/\"//g')
    sdir=$(echo  ${sarr[$idx]} | sed -s 's/\"//g')

    if [ -d "${sdir}" ]; then
      add_n "${cname} "
      echo ""
      echo ">>> $idx: [${cname}],  ${sdir}"
      do_backup ${cname} ${sdir}
    else
      echo "WARNING: dir '${sdir}' does not exist!"
     add_n "<dir not existing: '${sdir}'!>"
    fi
  done
  add_n "]"
}

send_gotify() {
#  echo ">>> send_gotify: $1, $2, $3 $4"
  curl "$1/message?token=$2" -F "title=$3" -F "message=$4" -F "priority=${GOTIFY_PRIORITY}" -o /dev/null --silent
}

send_notification() {
  ntype=$(jq '.notification.type' ${backup_config_file} | sed -s 's/\"//g' )

  case "$ntype" in
    "gotify")
      echo "sending notification via gotify"
      url=$(jq '.notification.url' ${backup_config_file} | sed -s 's/\"//g' )
      token=$(jq '.notification.token' ${backup_config_file} | sed -s 's/\"//g' )
#     echo "GOTIFY: $url, $token"

      send_gotify "${url}" "${token}" "DOCKER backup `hostname -A`" "$notification"
      ;;
    "console")
      echo "RESULT: ${notification}"
      ;;
    *)
      echo "skipping notiifcation (ntype=$ntype)"
      ;;
  esac
}

list_backup_folder() {
  echo "existing backups (${backup_dir}) :"
  echo ""
  bups=`ls -lah $backup_dir`
  echo "$bups"
}

backup_all

echo ""
echo "backup processing done."
echo ""

list_backup_folder

add_n ", backup done."

send_notification
echo ""
echo ""
echo "done."
