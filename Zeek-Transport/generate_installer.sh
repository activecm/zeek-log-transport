#!/usr/bin/env bash

set -e

# Store the absolute path of the script's dir and switch to the top dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pushd "$SCRIPT_DIR" > /dev/null

__help() {
  cat <<HEREDOC
This script generates an installer for setting up Zeek data transfers to AC-Hunter.
The resulting file is not intended to be installed directly by customers.
Usage:
  ${_NAME} [<arguments>]
Options:
  -h|--help     Show this help message.
HEREDOC
}

# Parse through command args
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      # Display help and exit
      __help
      exit 0
      ;;
    *)
    ;;
  esac
  shift
done

# File/ Directory Names
TRANSPORT_ARCHIVE=Zeek-Transport
STAGE_DIR="$SCRIPT_DIR/stage/$TRANSPORT_ARCHIVE"

echo "Creating Zeek installer archive..."
# This has the result of only including the files we want
# but putting them in a single directory so they extract nicely
tar -C "$STAGE_DIR/.."  --exclude '.*' -chf "$SCRIPT_DIR/${TRANSPORT_ARCHIVE}.tar" $TRANSPORT_ARCHIVE

popd > /dev/null
