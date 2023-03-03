#!/usr/bin/env bash
#Copyright 2020 Active Countermeasures
#Performs installation of Zeek

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
    echo2 "Installation failed on line $1:$2."
    echo2 ""
    exit 1
}

__int() {
    echo2 ""
    echo2 "Installation cancelled."
    echo2 ""
    exit 1
}

trap '__err ${BASH_SOURCE##*/} $LINENO' ERR
trap '__int' INT

# Load the function library
. ./scripts/shell-lib/acmlib.sh
normalize_environment

#### Script Constants

#### Init State
# These variables could be sourced from a configuration script
# in order to support unattended installation.

ach_ip="$ach_ip"

#### Working State

#### Main Logic

print_usage_text () {
    cat >&2 <<EOHELP
This script will set up routine data transfers of Zeek data to AC-Hunter.
If the environment variable "ach_ip" is set, the value will be used for
AC-Hunter's IP address or hostname. Otherwise, the installer will present
a prompt asking for the information.
EOHELP
}

parse_parameters () {
    # Reads input parameters into the the Init State variables
    if [ "$1" = 'help' -o "$1" = '--help' ]; then
        print_usage_text
        exit 0
    fi
}

test_system () {
    status "Checking minimum requirements"
    require_supported_os
    require_selinux_permissive
    require_free_space_MB "/" "/usr" 5120
}

main () {
    parse_parameters "$@"

    status "Checking for administrator privileges"
    require_sudo
    export acm_no_interactive

    test_system

    status "Installing supporting software"
    ensure_common_tools_installed

    scripts/install_data_import.sh $ach_ip
}

main "$@"

#### Clean Up
# Change back to the initial working directory
popd > /dev/null
