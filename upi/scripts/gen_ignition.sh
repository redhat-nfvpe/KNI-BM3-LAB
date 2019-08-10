#!/bin/bash

usage() {
    cat <<-EOM
    Generate ignition files

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir]  
            Parse manifest files and generate intermediate variable files

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $DNSMASQ_DIR...]
EOM
    exit 0
}

VERBOSE="false"
export VERBOSE

while getopts ":hvm:o:" opt; do
    case ${opt} in
    o)
        out_dir=$OPTARG
        ;;
    m)
        manifest_dir=$OPTARG
        ;;
    v)
        VERBOSE="true"
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
source "$PROJECT_DIR/scripts/paths.sh"

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

prep_host_setup_src="$manifest_dir/prep_bm_host.src"
prep_host_setup_src=$(realpath "$prep_host_setup_src")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$prep_host_setup_src"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$OPENSHIFT_DIR}
out_dir=$(realpath "$out_dir")

parse_manifests "$manifest_dir"
map_cluster_vars
map_worker_vars

if [ ! -f "$manifest_dir/install-config.yaml" ]; then
    printf "%s does not exists, create!" "$manifest_dir/install-config.yaml"
    exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir"
cp "$manifest_dir/install-config.yaml" "$out_dir"

if ! openshift-install --log-level warn --dir "$out_dir" create ignition-configs > /dev/null; then
    printf "openshift-install create ignition-configs failed!\n"
    exit 1
fi

if [ ! -f "${FINAL_VALS[bootstrap_ign_file]}" ] || [ ! -f "${FINAL_VALS[master_ign_file]}" ]; then
    printf "terraform cluster vars expects ignition files in the following places...\n"
    printf "\t%s\n" "bootstrap_ign_file = ${FINAL_VALS[bootstrap_ign_file]}"
    printf "\t%s\n" "master_ign_file = ${FINAL_VALS[master_ign_file]}"
    printf "The following Ignition files were generated\n"
    for f in "$out_dir"/*.ign; do
        printf "\t%s\n" "$f"
    done
    printf "Need to correct paths...\n"

    exit 1
fi
