#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export SCRIPTDIR


check_var() {

    if [ "$#" -ne 2 ]; then
        echo "${FUNCNAME[0]} requires 2 arguements, varname and config_file...($(caller))"
        exit 1
    fi

    local varname=$1
    local config_file=$2

    if [ -z "${!varname}" ]; then
        echo "$varname not set in ${config_file}, must define $varname"
        exit 1
    fi
}

check_regular_file_exists() {
    cfile="$1"

    if [ ! -f "$cfile" ]; then
        echo "file does not exist: $cfile"
        exit 1
    fi
}

check_directory_exists() {
    dir="$1"

    if [ ! -d "$dir" ]; then
        echo "directory does not exist: $dir"
        exit 1
    fi
}

join_by() {
    local IFS="$1"
    shift
    echo "$*"
}
