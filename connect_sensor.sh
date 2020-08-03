#!/bin/bash
#This script should be runnable as either a downloaded script or as a script pulled with curl and fed directly to bash.  Note all input/output must be to &2
#Copyright 2020, Active Countermeasures

#FIXME - check path for final script
#FIXME Consider allowing user to set custom sensor name
#FIXME - make sure you run this on the AI-Hunter server:	cd /opt ; if [ ! -e zeek ]; then sudo ln -sf bro zeek ; fi

#Version 0.1.1

#======== Help text
	if [ "z$1" = "z--help" -o "z$1" = "z-h" -o "$1" = "my.aihunter.system" ]; then
		echo 'This script will set up regular transfer of Zeek or Bro logs to an AI-Hunter system.  This should be run as a (non-root) user that can read the Zeek/Bro logs.' >&2
		echo 'If you have the ssh keypair used on the AI-Hunter server (id_rsa_dataimport and id_rsa_dataimport.pub), please place these files in ~/.ssh/ before running.' >&2
		echo '' >&2
		echo 'In both of the following samples, you must replace "my.aihunter.system" with the hostname or IP of your AI-Hunter system.' >&2
		echo 'The optional second command line parameter is the local directory containing your zeek logs.  It is autodetected if not provided.' >&2
		echo 'This is the directory that contains a symlink called current and multiple directories whose names fit the pattern YYYY-MM-DD .' >&2
		echo '' >&2
		echo 'Sample call to execute directly:' >&2
		echo '   curl -fsSL https://raw.githubusercontent.com/activecm/zeek-log-transport/master/connect_sensor.sh -o - | /bin/bash -s my.aihunter.system [/zeek/log/top/dir/]' >&2
		echo '' >&2
		echo 'Sample call to download and run locally:' >&2
		echo '   curl -fsSL https://raw.githubusercontent.com/activecm/shell-lib/master/acmlib.sh' >&2
		echo '   curl -fsSL https://raw.githubusercontent.com/activecm/zeek-log-transport/master/connect_sensor.sh' >&2
		echo '   curl -fsSL https://raw.githubusercontent.com/activecm/zeek-log-transport/master/zeek_log_transport.sh' >&2
		echo '   chmod 755 connect_sensor.sh' >&2
		echo '   ./connect_sensor.sh my.aihunter.system [/zeek/log/top/dir/]' >&2
		echo '' >&2
		echo 'If this system cannot download these files directly, get all three files on a system that can, transfer them here, and run them here.' >&2
		exit 1
	fi

#======== Variables
	default_user_on_aihunter='dataimport'


#======== Support procedures
	#Load acmlib.sh if unable to find askYN as function
	if [ "`type -t askYN`" != 'function' ]; then
		if [ ! -w ./ ]; then
			echo "Unable to write to current directory, exiting." >&2
			exit 1
		fi
		echo "Now attempting to download the support library.  If this script exits it's because it was unable to download the library with curl or wget." >&2
		if [ ! -r ./acmlib.sh ]; then
			if type -path curl >/dev/null 2>&1 ; then
				curl -fsSL -O https://raw.githubusercontent.com/activecm/shell-lib/master/acmlib.sh || exit 1
			elif type -path wget >/dev/null 2>&1 ; then
				wget -O acmlib.sh https://raw.githubusercontent.com/activecm/shell-lib/master/acmlib.sh || exit 1
			else
				echo 'Unable to download acmlib.sh, exiting.' >&2
				exit 1
			fi
		fi
		. ./acmlib.sh
	fi

	if [ "`type -t askYN`" != 'function' ]; then
		echo "Unable to load acmlib.sh support script, exiting." >&2
		exit 1
	fi


#======== Check environment
	#Install rsync if not already installed
	rsync --version >/dev/null 2>&1 || sudo apt-get -y install rsync >/dev/null 2>&1 || sudo yum -y install rsync >/dev/null 2>&1

	#Needed tools (Note, a few of these are requirements for zeek_log_transport.sh itself)
	require_util awk cat chown chmod curl cut date egrep find grep hostname ip nice rsync sed ssh sort ssh-keygen sudo tr wget whoami

	#Find username of current user
	my_user=`whoami`
	if [ "$my_user" = "root" ]; then
		echo2 "This script is not intended to be run as root.  We strongly suggest running this as a normal user; press ctrl-c if you wish to exit and restart as a normal user.  Otherwise, wait 15 seconds and this will continue as root."
		exit 15
	fi

	#Check that AI-Hunter hostname/IP is $1.  If not, prompt for hostname/IP.
	if [ -n "$1" ]; then
		raw_aih_location="$1"
	else
		echo2 "What is the hostname (or IP address or ssh stanza name) of your AI-Hunter server?"
		read raw_aih_location <&2
	fi

	if echo "$raw_aih_location" | grep -q '@' ; then
		#User has supplied an "@" symbol in target system, do not add $default_user_on_aihunter
		aih_location="${raw_aih_location}"
	else
		#No "@" symbol in target system, force username to $default_user_on_aihunter
		aih_location="${default_user_on_aihunter}@${raw_aih_location}"
	fi


	#Check that local ssh keypair exists.
	if [ -s "$HOME/.ssh/id_rsa_dataimport" -a -s "$HOME/.ssh/id_rsa_dataimport.pub" ]; then
		if ! can_ssh "$aih_location" "-o" 'PasswordAuthentication=no' -i "$HOME/.ssh/id_rsa_dataimport" ; then
			status "Transferring the RSA key to $aih_location - please provide the password when prompted.  You may be prompted to accept the ssh host key."
			cat "$HOME/.ssh/id_rsa_dataimport.pub" 2>/dev/null \
			 | ssh "$aih_location" 'mkdir -p .ssh ; cat >>.ssh/authorized_keys ; chmod go-rwx ./ .ssh/ .ssh/authorized_keys'
		fi

	#If it doesn't exist, create the pair.  Then transfer the public key across, warning the user that a password will be requested.
	elif [ ! -e "$HOME/.ssh/id_rsa_dataimport" -a ! -e "$HOME/.ssh/id_rsa_dataimport.pub" ]; then
		#Create ssh key if it doesn't exist, and push to aihunter server or ask user to do so.
		status "Creating a new RSA key with no passphrase"
		ssh-keygen -b 2048 -t rsa -N '' -f "$HOME/.ssh/id_rsa_dataimport"
		status "Transferring the RSA key to $aih_location - please provide the password when prompted.  You may be prompted to accept the ssh host key."
		cat "$HOME/.ssh/id_rsa_dataimport.pub" 2>/dev/null \
		 | ssh "$aih_location" 'mkdir -p .ssh ; cat >>.ssh/authorized_keys ; chmod go-rwx ./ .ssh/ .ssh/authorized_keys'

	#If only one file of the pair exists warn and exit
	elif [ -e "$HOME/.ssh/id_rsa_dataimport" -a ! -e "$HOME/.ssh/id_rsa_dataimport.pub" ]; then
		fail "Private key exists, but not public."
	elif [ ! -e "$HOME/.ssh/id_rsa_dataimport" -a -e "$HOME/.ssh/id_rsa_dataimport.pub" ]; then
		fail "Public key exists, but not private."
	fi

	local_tld=''
	#Check $2 (if set) and common log directories to find where the logs are.
	for potential_local_tld in $2 /opt/zeek/logs/ /usr/local/zeek/logs/ /var/lib/docker/volumes/var_log_zeek/_data/ /nsm/zeek/logs /storage/zeek/logs/ /opt/bro/logs/ /usr/local/bro/logs/ /var/lib/docker/volumes/var_log_bro/_data/ /nsm/bro/logs /storage/bro/logs/ ; do
		if [ -n "$potential_local_tld" -a -d "$potential_local_tld" -a -r "$potential_local_tld" -a -L "$potential_local_tld/current" ]; then
			local_tld="$potential_local_tld"
			break			#Once we found the log dir, stop looking at the rest.
		fi
	done

	if [ "$local_tld" = '' ]; then
		fail "Unable to locate a local directory containing zeek logs."
	fi

	#Confirm that we can _read_ files from this tree.
	unreadable_files=`find "$local_tld" -type f -mtime -3 -iname '*.gz' \! -readable`
	if [ -n "$unreadable_files" ]; then
		fail "It appears there are files under $local_tld that are unreadable by $my_user .  Is there a permission problem?"
	fi


#======== Inform user of what will be done.
	echo2 "This script will set up an automated log transfer from the $local_tld directory on this system to $aih_location ."


#======== Install zeek_log_transport.sh
	#If it's not already in /usr/local/bin...
	if [ ! -s /usr/local/bin/zeek_log_transport.sh -o ! -x /usr/local/bin/zeek_log_transport.sh ]; then
		echo2 "You may be prompted for your local password to run commands under sudo."

		#If it exists in the current directory, copy it
		if [ -s ./zeek_log_transport.sh ]; then
			sudo cp -p ./zeek_log_transport.sh /usr/local/bin/zeek_log_transport.sh
		#If it doesn't exist in the current directory, download zeek_log_transport.sh
		else	#Download and install it
			cd /usr/local/bin/
			if type -path curl >/dev/null 2>&1 ; then
				sudo curl -s https://raw.githubusercontent.com/activecm/zeek-log-transport/master/zeek_log_transport.sh -O
			elif type -path wget >/dev/null 2>&1 ; then
				sudo curl -s https://raw.githubusercontent.com/activecm/zeek-log-transport/master/zeek_log_transport.sh -O zeek_log_transport.sh
			fi
			cd -
		fi
		sudo chown root.root /usr/local/bin/zeek_log_transport.sh
		sudo chmod 755 /usr/local/bin/zeek_log_transport.sh
	fi

#======== Test that we can ssh to $1 (note that the user may need to accept ssh host key and explain how to confirm it)
	echo2 "Confirming that we can ssh to $aih_location using the ssh authentication key.  You may be prompted to accept the ssh host key."
	if ! can_ssh "$aih_location" "-o" 'PasswordAuthentication=no' -i $HOME/.ssh/id_rsa_dataimport ; then
		fail "Unable to ssh to $aih_location using the ssh keypair."
	fi


#======== Run zeek_log_transport.sh to do a first pass transfer using supplied/located local log directory
	/usr/local/bin/zeek_log_transport.sh --dest "$aih_location" --localdir "$local_tld"

	###########Confirm that the target directory exists (possible future check)



#======== If /etc/cron.d/bro_log_transport exists, renamed to /etc/cron.d/zeek_log_transport and fix called command.
	cron_restart_needed="no"
	if [ -e /etc/cron.d/bro_log_transport -a ! -e /etc/cron.d/zeek_log_transport ]; then
		sudo mv /etc/cron.d/bro_log_transport /etc/cron.d/zeek_log_transport
		sudo sed -i "s|/usr/local/bin/bro_log_transport.sh|/usr/local/bin/zeek_log_transport.sh|g" /etc/cron.d/zeek_log_transport
		cron_restart_needed="yes"
	fi

	#If none, create /etc/cron.d/zeek_log_transport and add command to send logs
	if ! grep -qs '/usr/local/bin/zeek_log_transport.sh --dest '"${aih_location}"'' /etc/cron.d/zeek_log_transport ; then
		#We don't already have this line in that file, so add it.
		#This runs the log transport at 5 minutes past every hour.
		echo "5 * * * * $my_user /usr/local/bin/zeek_log_transport.sh --dest $aih_location --localdir $local_tld" | sudo tee -a /etc/cron.d/zeek_log_transport >/dev/null
		cron_restart_needed="yes"
	fi


	#======== Restart cron
	if [ "$cron_restart_needed" = "yes" ]; then
		sudo service cron reload 2>/dev/null
		sudo service crond reload 2>/dev/null
	fi


#======== Notify the user that the logs will go over during the next 24 hours and that they'll see results in AI-Hunter within 2 or 3 hours.
	echo2 "The setup is complete.  Zeek/Bro logs under $local_tld will be transferred hourly to $aih_location .  You should start to see this sensor in AI-Hunter in the next few hours."



	exit 0
