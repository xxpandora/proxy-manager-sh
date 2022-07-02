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
log "Stopping services"
systemctl stop openresty

if [ -f /lib/systemd/system/pegaflare-waf.service ]; then
  systemctl stop pegaflare-waf
fi

# Cleanup for new install
log "Cleaning old files"
rm -rf /app
runcmd rm -rf /data
runcmd rm -rf /etc/letsencrypt.ini
runcmd rm -rf /etc/environment

# Install nodejs
log "Installing nodejs"
runcmd wget -qO - https://deb.nodesource.com/setup_16.x | bash -
runcmd apt-get install -y -q --no-install-recommends nodejs
runcmd npm install --global yarn

# Get latest version information for PegaFlare
log "Checking for latest PegaFlare release"
runcmd 'wget $WGETOPT -O ./_latest_release $NPMURL/releases/latest'
_latest_version=$(basename $(cat ./_latest_release | grep -wo "xxpandora/.*.tar.gz") .tar.gz | cut -d'v' -f2)

# Download PegaFlare WAF source
log "Downloading PegaFlare v$_latest_version"
runcmd 'wget $WGETOPT -c $NPMURL/archive/v$_latest_version.tar.gz -O - | tar -xz'
cd ./nginx-proxy-manager-$_latest_version

# Update PegaFlare version in package.json files
sed -i "s+0.0.0+$_latest_version+g" backend/package.json
sed -i "s+0.0.0+$_latest_version+g" frontend/package.json

# Fix nginx config files for use with openresty defaults
sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
for NGINX_CONF in $NGINX_CONFS; do
  sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
done

# Copy runtime files
log "Copy runtime files"
cp -r docker/rootfs/var/www/html/* /var/www/html/
cp -r docker/rootfs/etc/nginx/* /etc/nginx/
cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
rm -f /etc/nginx/conf.d/dev.conf

# Create required folders
log "Create required folders"
mkdir -p /data/nginx \
/data/custom_ssl \
/data/logs \
/data/access \
/data/nginx/default_host \
/data/nginx/default_www \
/data/nginx/proxy_host \
/data/nginx/redirection_host \
/data/nginx/stream \
/data/nginx/dead_host \
/data/nginx/temp

# Generate dummy self-signed certificate.
log "Generating dummy SSL certificate"
rm -rf /data/nginx/dummycert.pem
runcmd openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=PegaFlare WAF/OU=Dummy Certificate/CN=pegaflare.local" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem

# Copy app files
log "Copy app files"
mkdir -p /app/global /app/frontend/images
cp -r backend/* /app
cp -r global/* /app/global

# Build the frontend
log "Building frontend"
cd ./frontend
export NODE_ENV=development
runcmd yarn install --network-timeout=30000
runcmd yarn build
cp -r dist/* /app/frontend
cp -r app-images/* /app/frontend/images

# Initialize backend
log "Initializing backend"
rm -rf /app/config/default.json &>/dev/null
if [ ! -f /app/config/production.json ]; then
cat << 'EOF' > /app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
fi
cd /app
export NODE_ENV=development
runcmd yarn install --network-timeout=30000

# Start services
log "Starting services"
systemctl daemon-reload
systemctl start openresty
systemctl start pegaflare-waf

IP=$(hostname -I | cut -f1 -d ' ')
log "Installation complete

\e[0mPegaFlare WAF should be reachable at the following URL.

      URL       : http://${IP}:81
      USER      : admin@example.com
      PASSWORD  : changeme
"
