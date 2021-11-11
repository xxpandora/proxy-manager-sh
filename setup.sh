#!/usr/bin/env sh
TMP=/tmp/pegacdn_install.sh
URL=https://raw.githubusercontent.com/xxpandora/proxy-manager-sh/main/install

if [ "$(uname)" != "Linux" ]; then
  echo "OS NOT SUPPORTED"
  exit 1
fi

DISTRO=$(cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '"')
if [ "$DISTRO" != "alpine" ] && [ "$DISTRO" != "ubuntu" ]; then
  echo "DISTRO NOT SUPPORTED"
  exit 1
fi

rm -rf $TMP
wget -O "$TMP" "$URL/$DISTRO.sh"

chmod +x "$TMP"

if [ "$(command -v bash)" ]; then
  bash "$TMP"
else
  sh "$TMP"
fi

