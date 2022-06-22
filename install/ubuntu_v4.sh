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

  # Cleanup environment
  log "Cleanup environment"
  rm -rf /root/.cache
  rm -rf /etc/environment
 
  # Cleanup for new install
  log "Cleaning old files"
  rm -rf /app \
  /data \
  /var/www/html \
  /etc/nginx \
  /var/log/nginx \
  /var/lib/nginx \
  /var/cache/nginx \
  /etc/environment \
  /usr/local/openresty \ &>/dev/null
fi

# Install dependencies
log "Installing dependencies"
rm -rf /etc/environment
runcmd apt-get update
export DEBIAN_FRONTEND=noninteractive
runcmd 'apt-get install -y --no-install-recommends $DEVDEPS gnupg openssl ca-certificates apache2-utils logrotate'

# Install Python
log "Installing python"
runcmd apt-get install -y -q --no-install-recommends python3 python3-distutils python3-venv
python3 -m venv /opt/certbot/
export PATH=/opt/certbot/bin:$PATH
grep -qo "/opt/certbot" /etc/environment || echo "$PATH" > /etc/environment
# Install certbot and python dependancies
runcmd wget -qO - https://bootstrap.pypa.io/get-pip.py | python -
if [ "$(getconf LONG_BIT)" = "32" ]; then
  runcmd pip install --no-cache-dir -U cryptography==3.3.2
fi
runcmd pip install --no-cache-dir cffi certbot

# Install openresty
log "Installing openresty"
wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add -
_distro_release=$(wget $WGETOPT "http://openresty.org/package/$DISTRO_ID/dists/" -O - | grep -o "$DISTRO_CODENAME" | head -n1 || true)
if [ $DISTRO_ID = "ubuntu" ]; then
  echo "deb [trusted=yes] http://openresty.org/package/$DISTRO_ID ${_distro_release:-focal} main" | tee /etc/apt/sources.list.d/openresty.list
else
  echo "deb [trusted=yes] http://openresty.org/package/$DISTRO_ID ${_distro_release:-bullseye} openresty" | tee /etc/apt/sources.list.d/openresty.list
fi
runcmd apt-get update && apt-get install -y -q --no-install-recommends openresty

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

# Crate required symbolic links
log "Setting up symbolic links"
ln -sf /usr/bin/python3 /usr/bin/python
ln -sf /opt/certbot/bin/pip /usr/bin/pip
ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx
ln -sf /usr/local/openresty/nginx/ /etc/nginx

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
mkdir -p /var/www/html /etc/nginx/logs
cp -r docker/rootfs/var/www/html/* /var/www/html/
cp -r docker/rootfs/etc/nginx/* /etc/nginx/
cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
cp docker/rootfs/etc/logrotate.d/pegaflare-waf-manager /etc/logrotate.d/pegaflare-waf-manager
ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
rm -f /etc/nginx/conf.d/dev.conf

# Create required folders
log "Create required folders"
mkdir -p /tmp/nginx/body \
/run/nginx \
/data/nginx \
/data/custom_ssl \
/data/logs \
/data/access \
/data/nginx/default_host \
/data/nginx/default_www \
/data/nginx/proxy_host \
/data/nginx/redirection_host \
/data/nginx/stream \
/data/nginx/dead_host \
/data/nginx/temp \
/var/lib/nginx/cache/public \
/var/lib/nginx/cache/private \
/var/cache/nginx/proxy_temp

chmod -R 777 /var/cache/nginx
chown root /tmp/nginx

# Dynamically generate resolvers file, if resolver is IPv6, enclose in `[]`
# thanks @tfmm
echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" > /etc/nginx/conf.d/include/resolvers.conf

# Generate dummy self-signed certificate.
if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]; then
  log "Generating dummy SSL certificate"
  runcmd 'openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=PegaFlare WAF/OU=Dummy Certificate/CN=pegaflare.local" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem'
fi

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

# Create PegaFlare service
log "Creating PegaFlare service"
cat << 'EOF' > /lib/systemd/system/pegaflare-waf.service
[Unit]
Description=PegaFlare WAF
After=network.target
Wants=openresty.service

[Service]
Type=simple
Environment=NODE_ENV=production
ExecStartPre=-/bin/mkdir -p /tmp/nginx/body /data/letsencrypt-acme-challenge
ExecStart=/usr/bin/node index.js --abort_on_uncaught_exception --max_old_space_size=250
WorkingDirectory=/app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pegaflare-waf

# Start services
log "Starting services"
runcmd systemctl reload openresty
runcmd systemctl restart openresty
runcmd systemctl start pegaflare-waf

IP=$(hostname -I | cut -f1 -d ' ')
log "Installation complete

\e[0mPegaFlare WAF should be reachable at the following URL.

      URL       : http://${IP}:81
      USER      : admin@example.com
      PASSWORD  : changeme
"
