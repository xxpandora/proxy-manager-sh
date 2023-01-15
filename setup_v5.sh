#!/bin/bash
# shellcheck disable=SC1090,SC2086,SC2034

if [[ $EUID -ne 0 ]]; then
	echo -e "Sorry, you need to run this as root"
	exit 1
fi

TMP=/tmp/pegacdn_install.sh
INSTALL_URL=https://raw.githubusercontent.com/xxpandora/proxy-manager-sh/main/install
UPDATE_URL=https://raw.githubusercontent.com/xxpandora/proxy-manager-sh/main/update
DELETE_URL=https://raw.githubusercontent.com/xxpandora/proxy-manager-sh/main/delete

INSTALL_SCRIPT=ubuntu_install
UPDATE_SCRIPT=ubuntu_update
DELETE_SCRIPT=ubuntu_delete

# Define installation parameters for headless install (fallback if unspecifed)
if [[ $HEADLESS == "y" ]]; then
	OPTION=${OPTION:-1}
fi


# Clean screen before launching menu
if [[ $HEADLESS == "n" ]]; then
	clear
fi

if [[ $HEADLESS != "y" ]]; then
	echo ""
	echo "Welcome to the setup script."
	echo ""
	echo "What do you want to do?"
	echo "   1) Install script"
	echo "   2) Update script"
	echo "   3) Uninstall script"
	echo "   4) Exit"
	echo ""
	while [[ $OPTION != "1" && $OPTION != "2" && $OPTION != "3" && $OPTION != "4" ]]; do
		read -rp "Select an option [1-4]: " OPTION
	done
fi

case $OPTION in
1)

	# Install
		rm -rf $TMP
		wget --no-check-certificate --no-cache --no-cookies -O "$TMP" "$INSTALL_URL/$INSTALL_SCRIPT.sh"

		chmod +x "$TMP"

		if [ "$(command -v bash)" ]; then
			$(command -v sudo) bash "$TMP"
		else
			sh "$TMP"
		fi
	echo ""
	echo "Installation done."
	sleep 2
	./setup_v5.sh
	exit
	;;

2)

	# Update
		rm -rf $TMP
		wget --no-check-certificate --no-cache --no-cookies -O "$TMP" "$UPDATE_URL/$UPDATE_SCRIPT.sh"

		chmod +x "$TMP"

		if [ "$(command -v bash)" ]; then
			$(command -v sudo) bash "$TMP"
		else
			sh "$TMP"
		fi
	echo ""
	echo "Update done."
	sleep 2
	./setup_v5.sh
	exit
	;;

3)

	# Delete
		rm -rf $TMP
		wget --no-check-certificate --no-cache --no-cookies -O "$TMP" "$DELETE_URL/$DELETE_SCRIPT.sh"

		chmod +x "$TMP"

		if [ "$(command -v bash)" ]; then
			$(command -v sudo) bash "$TMP"
		else
			sh "$TMP"
		fi
	echo ""
	echo "Delete done."
	sleep 2
	./setup_v5.sh
	exit
	;;

*) # Exit
	exit
	;;

esac
