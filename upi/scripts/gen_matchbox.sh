#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"

declare -A OPENSHIFT_RHCOS_ASSET_MAP=(
    ["rhcos-4.1.0-x86_64-installer-initramfs.img"]="$OPENSHIFT_RHCOS_URL"
    ["rhcos-4.1.0-x86_64-installer-kernel"]="$OPENSHIFT_RHCOS_URL"
    ["rhcos-4.1.0-x86_64-metal-bios.raw.gz"]="$OPENSHIFT_RHCOS_URL"
    ["rhcos-4.1.0-x86_64-metal-uefi.raw.gz"]="$OPENSHIFT_RHCOS_URL"
)

SHA256_FILE="sha256sum.txt"
SHA256_URL="$OPENSHIFT_RHCOS_URL/$SHA256_FILE"

export OPENSHIFT_RHCOS_ASSET_MAP

MATCHBOX_REPO="https://github.com/poseidon/matchbox.git"

CONTAINTER_NAME="matchbox"

set -o pipefail

usage() {
    cat <<-EOM
    Generate files related to $CONTAINTER_NAME

    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-v] [-m manfifest_dir] assets|certs|start|stop|remove
            repo     - clone the %CONTAINTER_NAME repo located at $MATCHBOX_REPO
            assets   - Download assets for $CONTAINTER_NAME
            certs    - Generate certs for $CONTAINTER_NAME
            start    - Start the $CONTAINTER_NAME container 
            stop     - Stop the $CONTAINTER_NAME container
            remove   - Stop and remove the $CONTAINTER_NAME container

    Options
        -v verbose
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
EOM
    exit 0
}

make_clone() {
    make_dirs

    [ -d "$MATCHBOX_DIR/.git" ] && return

    if ! git clone "$MATCHBOX_REPO"; then
        printf "Error cloning %s!\n" "$MATCHBOX_REPO"
        exit 1
    fi
}

start_matchbox() {

    if podman ps --all | grep "$CONTAINTER_NAME" >/dev/null; then
        printf "Container already exists, removing and starting...\n"
        podman stop "$CONTAINTER_NAME" >/dev/null 2>&1
        if ! podman rm "$CONTAINTER_NAME" >/dev/null; then
            printf "Could not remove \"%s\"" "$CONTAINTER_NAME"
            exit 1
        fi
    fi

    if ! cid=$(podman run -d --net=host --name "$CONTAINTER_NAME" -v "$MATCHBOX_VAR_LIB:/var/lib/matchbox:Z" \
        -v "$MATCHBOX_ETC_DIR:/etc/matchbox:Z,ro" quay.io/poseidon/matchbox:latest -address=0.0.0.0:8080 \
        -rpc-address=0.0.0.0:8081 -log-level=debug); then
        printf "Could not start %s container!\n" "$CONTAINTER_NAME"
        exit 1
    fi
    run_status=$(podman inspect $CONTAINTER_NAME | jq .[0].State.Running)
    if [[ "$run_status" =~ false ]]; then
        printf "Failed to start container...\n"
        podman logs "$CONTAINTER_NAME"
    else
        printf "Started %s as id %s\n" "$CONTAINTER_NAME" "$cid"
    fi

}

download_assets() {

    make_dirs

    (
        if cd "$MATCHBOX_VAR_LIB/assets"; then
            if ! curl -sS -O "$SHA256_URL"; then
                printf "Unable to fetch: %s" "$SHA256_URL"
            fi

            declare -A SHAMAP

            while read -r line; do
                read -ra a <<<"$line"
                SHAMAP[${a[1]}]=${a[0]}
            done <"$SHA256_FILE"

            for asset in "${!OPENSHIFT_RHCOS_ASSET_MAP[@]}"; do
                if [ -f "$asset" ] && sum=$(sha256sum "$asset"); then
                    sum=${sum%% *}
                    if [[ ${SHAMAP[$asset]} == "$sum" ]]; then
                        printf "%s already present with correct sha256sum..skipping...\n" "$asset"
                        continue
                    fi
                fi
                url="${OPENSHIFT_RHCOS_ASSET_MAP[$asset]}"
                printf "Fetching %s...\n" "$url/$asset"
                curl -O "$url/$asset"
            done
        else
            printf "Failed to download assets..."
            exit 1
        fi
    )
}

make_certs() {

    (
        if cd "$MATCHBOX_DIR/scripts/tls"; then
            SAN="IP.1:$(nthhost "$PROV_IP_CIDR" 10)"
            export SAN

            if ./cert-gen; then
                cp ca.crt server.crt server.key "$MATCHBOX_DATA_DIR/etc/matchbox"
                cp ca.crt client.crt client.key ~/.matchbox
            else
                printf "cert-gen failed!"
                exit 1
            fi
        else
            printf "%s does not exist, 'gen_matchbox.sh clone-repo' first?" "$MATCHBOX_DIR/scripts/tls"
            exit 1
        fi
    )
}

make_dirs() {

    mkdir -p ~/.matchbox
    mkdir -p "$MATCHBOX_DIR" || exit 1
    mkdir -p "$MATCHBOX_ETC_DIR" || exit 1
    mkdir -p "$MATCHBOX_VAR_LIB" || exit 1
    mkdir -p "$MATCHBOX_VAR_LIB/assets" || exit 1
}

VERBOSE="false"
export VERBOSE

while getopts ":hm:v" opt; do
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

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    COMMAND="all"
fi

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi

# shellcheck disable=SC1091
source "common.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

MATCHBOX_ETC_DIR="$MATCHBOX_DATA_DIR/etc/matchbox"
MATCHBOX_VAR_LIB="$MATCHBOX_DATA_DIR/var/lib/matchbox"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

prep_host_setup_src="$manifest_dir/prep_bm_host.src"
prep_host_setup_src=$(realpath "$prep_host_setup_src")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$prep_host_setup_src"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$COREDNS_DIR}
out_dir=$(realpath "$out_dir")

parse_manifests "$manifest_dir"

map_cluster_vars

case "$COMMAND" in
all) ;;
repo)
    make_clone
    ;;
assets)
    download_assets
    ;;
certs)
    make_certs
    ;;
start)
    start_matchbox
    ;;
stop)
    cid=$(podman stop "$CONTAINTER_NAME") && printf "Stopped %s\n" "$cid"
    ;;
remove)
    podman stop "$CONTAINTER_NAME" 2>/dev/null && podman rm "$CONTAINTER_NAME" >/dev/null
    ;;

*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
