#!/usr/bin/env bash
set -euo pipefail
trap trapexit EXIT SIGTERM

DISTRO_ID=$(cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '"')
DISTRO_CODENAME=$(cat /etc/*-release | grep -w VERSION_CODENAME | cut -d= -f2 | tr -d '"')

TEMPDIR=$(mktemp -d)
TEMPLOG="$TEMPDIR/tmplog"
TEMPERR="$TEMPDIR/tmperr"
LASTCMD=""
WGETOPT="-t 1 -T 15 -q"
DEVDEPS="git build-essential libffi-dev libssl-dev python3-dev"
NPMURL="https://github.com/xxpandora/nginx-proxy-manager"

cd $TEMPDIR
touch $TEMPLOG

# Helpers
log() { 
  logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g");
  clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
}
runcmd() { 
  LASTCMD=$(grep -n "$*" "$0" | sed "s/[[:blank:]]*runcmd//");
  if [[ "$#" -eq 1 ]]; then
    eval "$@" 2>$TEMPERR;
  else
    $@ 2>$TEMPERR;
  fi
}
trapexit() {
  status=$?
  
  if [[ $status -eq 0 ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g")
    clear && printf "\033c\e[3J$logs\n";
  elif [[ -s $TEMPERR ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/31/g" | sed -e "s/info/error/g")
    err=$(cat $TEMPERR | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g' | rev | cut -d':' -f1 | rev | cut -d' ' -f2-) 
    clear && printf "\033c\e[3J$logs\e[33m\n$0: line $LASTCMD\n\e[33;2;3m$err\e[0m\n"
  else
    printf "\e[33muncaught error occurred\n\e[0m"
  fi
}

# Check for previous install
if [ -f /lib/systemd/system/pegaflare-waf.service ]; then
  log "Stopping services"
  systemctl stop openresty
  systemctl stop pegaflare-waf
 
  # Cleanup for new install
  log "Cleaning old files"
  runcmd apt-get remove -y openresty
  rm -rf /app \
  /data \
  /var/www/html \
  /var/log/nginx \
  /var/lib/nginx \
  /var/cache/nginx \
  /etc/environment \
  /etc/apt/sources.list.d/openresty.list \ &>/dev/null
fi
 

# Uninstall openresty
log "Uninstall openresty"
runcmd sudo apt -y remove openresty*

# Cleanup environment
log "Cleanup environment"
rm -rf /root/.cache
rm -rf /etc/environment
rm -rf /etc/nginx
rm -rf /etc/openresty
rm -rf /usr/local/openresty
rm -rf /usr/sbin/nginx
rm -rf /etc/apt/sources.list.d/openresty.list
