#!/usr/bin/env sh
TMP=/tmp/pegacdn_install.sh
URL=https://raw.githubusercontent.com/xxpandora/proxy-manager-sh/main/install

INSTALL_SCRIPT=ubuntu_v4

rm -rf $TMP
wget -O "$TMP" "$URL/$INSTALL_SCRIPT.sh"

chmod +x "$TMP"

if [ "$(command -v bash)" ]; then
  $(command -v sudo) bash "$TMP"
else
  sh "$TMP"
fi

