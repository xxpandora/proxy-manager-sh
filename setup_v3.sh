#!/usr/bin/env sh
TMP=/tmp/pegacdn_install.sh
URL=https://raw.githubusercontent.com/xxpandora/proxy-manager-sh/main/install

if [ "$(uname)" != "Linux" ]; then
  echo "OS NOT SUPPORTED"
  exit 1
fi

DISTRO=$(cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '"')
if [ "$DISTRO" != "alpine" ] && [ "$DISTRO" != "ubuntu" ] && [ "$DISTRO" != "debian" ]; then
  echo "DISTRO NOT SUPPORTED"
  exit 1
fi

INSTALL_SCRIPT=$DISTRO

rm -rf $TMP
wget -O "$TMP" "$URL/$INSTALL_SCRIPT_v3.sh"

chmod +x "$TMP"

if [ "$(command -v bash)" ]; then
  $(command -v sudo) bash "$TMP"
else
  sh "$TMP"
fi

