# docker-backup-script
Simple Docker volumes backup tool

## Usage

./backup_docker.sh [options]

Usage examples:
       ./backup_docker.sh --help
       ./backup_docker.sh --template
       ./backup_docker.sh --backup /home/user/backup_config.json

Options:
  -h, --help
         print this help and exit

  -t, --template
         print a backup config template structure with locally found docker containers

  -b config, --backup config
         perform backup with configuratio
