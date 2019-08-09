#!/bin/bash

usage() {
    cat <<-EOM
    Parse the manifest files in the cluster director

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir]  
            Parse manifest files and generate intermediate variable files

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/dnsmasq/...]
EOM
    exit 0
}

VERBOSE="false"
export VERBOSE

while getopts ":hvm:" opt; do
    case ${opt} in
    v)
        VERBOSE="true"
        ;;
    m)
        manifest_dir=$OPTARG
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

# shellcheck disable=SC1091
source "common.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"

prep_host_setup_src="$PROJECT_DIR/cluster/prep_bm_host.src"
prep_host_setup_src=$(realpath "$prep_host_setup_src")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$prep_host_setup_src"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

manifest_dir=${manifest_dir:-$PROJECT_DIR/cluster}
manifest_dir=$(realpath "$manifest_dir")

parse_manifests "$manifest_dir"

mapfile -d '' sorted < <(printf '%s\0' "${!MANIFEST_VALS[@]}" | sort -z)

ofile="$manifest_dir/manifest_vals.sh"

printf "declare -A MANIFEST_VALS=(\n" > "$ofile"

for v in "${sorted[@]}"; do
    printf "  [%s]=\"%s\"\n" "$v" "${MANIFEST_VALS[$v]}" >> "$ofile"
done

printf ")\n" >> "$ofile"
printf "export MANIFEST_VALS\n" >> "$ofile"

