#!/usr/bin/env bash
#Copyright 2019 Active Countermeasures
#Installs the data import user account and zeek_log_transport.sh cron job.
#version = 2.0.1

#### Environment Set Up

# Set the working directory to the script directory
pushd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null

# Set exit on error
set -o errexit
set -o errtrace
set -o pipefail

# ERROR HANDLING
__err() {
    echo2 ""
    echo2 "Installation failed on line ${0##*/}:$1."
    echo2 ""
	exit 1
}

__int() {
    echo2 ""
	echo2 "Installation cancelled."
    echo2 ""
	exit 1
}

trap '__err $LINENO' ERR
trap '__int' INT

# Load the function library
. ./shell-lib/acmlib.sh
normalize_environment

#### Script Constants
data_import_private_key="$HOME/.ssh/id_rsa_dataimport"
data_import_public_key="$HOME/.ssh/id_rsa_dataimport.pub"

#### Init State
data_source_name=""
ach_ip=""

#### Main Logic
print_usage_text () {
    cat >&2 <<EOHELP
This script will and set up routine data transfers to AC-Hunter. This script
should not be called directly.

The first parameter should be set to the name of the software producing the
data which is being sent to AC-Hunter. The second parameter is an optional
IP address for AC-Hunter. If it is not set, the script will prompt the user
for the address. If the address is set to 127.0.0.1, nothing will be installed.

On the command line, enter:
$0 name-of-data-source [ip.address.for.achunter]
EOHELP
}

parse_parameters () {
	if [ -z "$1" ]; then
		print_usage_text
		exit 1
	fi
	data_source_name="$1"
	ach_ip="$2"
}

check_data_import_ip () {
    # Checks if the data import ip address is local or not. Returns true if it is.
    # If it isn't, it attempts to ssh under the dataimport account to the given ip
    # using the data import private key
    check_ssh_target_is_local "$ach_ip" || can_ssh "dataimport@$ach_ip" -i "$data_import_private_key" -o "StrictHostKeyChecking=no"
}

main() {
	parse_parameters "$@"
	require_sudo
    export acm_no_interactive

	#Only run this function if the data import private key has been
    #transferred in via install_acm.sh
	if [ ! -e "$data_import_private_key" ]; then
		status "Skipping data transfer set-up. SSH key does not exist."
        return 0
    fi

    if [ "$acm_no_interactive" = 'yes' ] && [ -z "$ach_ip" ]; then
        echo2 "No AC-Hunter IP address supplied, and we are in non-interactive mode.  Exiting."
        exit 1
    fi
    status "Configuring data transfer to AC-Hunter"
    while [ -z "$ach_ip" ] || ! check_data_import_ip ; do
		if [ -n "$ach_ip" -a -e "$data_import_public_key" ]; then
			echo2 "Please ensure $data_import_public_key has been added to /home/dataimport/.ssh/authorized_keys on $ach_ip."
		fi
	    echo2 "In order to transfer data from $data_source_name to AC-Hunter, we need to know the hostname or IP address of the AC-Hunter system."
        echo2 "Enter    127.0.0.1    if AC-Hunter is installed locally."
		prompt2 "Please enter the hostname or IP address of your AC-Hunter system: "
        read -e ach_ip <&2
    done

	if check_ssh_target_is_local "$ach_ip"; then
		echo2 "Skipping data transfer set-up. AC-Hunter is installed locally."
		return 0
	fi

	echo2 "$data_source_name is able to send data to AC-Hunter, good."

	status "Installing data transfer routine"

    $SUDO cp "zeek_log_transport.sh" /usr/local/bin/zeek_log_transport.sh

    # Remove bro_log_transport used in previous versions of this script if it exists
    if [ -f /usr/local/bin/bro_log_transport.sh ]; then
        $SUDO rm -f /usr/local/bin/bro_log_transport.sh
    fi
    # Migrate old cron job used in previous version of this script
    if [ -f /etc/cron.d/bro_log_transport ]; then
        $SUDO mv /etc/cron.d/bro_log_transport /etc/cron.d/zeek_log_transport
        $SUDO sed -i "s|/usr/local/bin/bro_log_transport.sh|/usr/local/bin/zeek_log_transport.sh|g" /etc/cron.d/zeek_log_transport
    fi

    if ! grep -qs '/usr/local/bin/zeek_log_transport.sh --dest '"${ach_ip}"'' /etc/cron.d/zeek_log_transport ; then
        #We don't already have this line in that file, so add it.
        #This runs the log transport at 5 minutes past every hour.
        echo "5 * * * * ${SUDO_USER:-$USER} /usr/local/bin/zeek_log_transport.sh --dest $ach_ip" | $SUDO tee -a /etc/cron.d/zeek_log_transport >/dev/null
    fi

    $SUDO service cron reload >/dev/null 2>&1 || : 		#Correct for Ubuntu 16.x
	$SUDO service crond reload >/dev/null 2>&1 || :		#Correct for CentOS 7

	if [ -n "$SUDO_USER" ]; then
		#Because the ssh tests (and host key harvesting) may have been performed as root, we need to copy any discovered host keys to the original user's known_hosts.
        cat /root/.ssh/known_hosts | tee -a "$HOME/.ssh/known_hosts" >/dev/null
		chown "$SUDO_USER" "$HOME/.ssh/known_hosts"
		chmod go-rwx "$HOME/.ssh/known_hosts"
	fi
	echo2 "Cron is set to transfer data to AC-Hunter every hour, good."
    echo2
}

main "$@"

#### Clean Up
# Change back to the initial working directory
popd > /dev/null
