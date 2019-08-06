#!/bin/bash

HAPROXY_IMAGE_NAME="akraino-haproxy"
HAPROXY_IMAGE_TAG="latest"
HAPROXY_CONTAINTER_NAME="akraino-haproxy"

set -o pipefail

usage() {
    cat <<-EOM
    Generate an haproxy config file

    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-s prep_bm_host.src] [-m manfifest_dir] [-o out_dir] 
            Generate config files for the baremetal interface

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/dnsmasq/...]
        -s [./../prep_host_setup.src -- Location of the config file for host prep
            Default to $PROJECT_DIR/cluster//prep_host_setup.src
EOM
    exit 0
}

gen_config_haproxy() {
    local out_dir="$1"
    local cfg_file="$out_dir/haproxy.cfg"
    local cluster_id="${FINAL_VALS[cluster_id]}"

    mkdir -p "$out_dir"

    cat <<EOF >"$cfg_file"
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

frontend kubeapi
    mode tcp
    bind *:6443
    option tcplog
    default_backend kubeapi-main

frontend mcs
    bind *:22623
    default_backend mcs-main
    mode tcp
    option tcplog

frontend http
    bind *:80
    mode tcp
    default_backend http-main
    option tcplog

frontend https
    bind *:443
    mode tcp
    default_backend https-main
    option tcplog

backend kubeapi-main
    balance source
    mode tcp
    server $cluster_id-bootstrap 192.168.111.10:6443 check
    server $cluster_id-master-0  192.168.111.11:6443 check
    server $cluster_id-master-1  192.168.111.12:6443 check
    server $cluster_id-master-2  192.168.111.13:6443 check

backend mcs-main
    balance source
    mode tcp
    server $cluster_id-bootstrap 192.168.111.10:22623 check
    server $cluster_id-master-0  192.168.111.11:22623 check
    server $cluster_id-master-1  192.168.111.12:22623 check
    server $cluster_id-master-2  192.168.111.13:22623 check

backend http-main
    balance source
    mode tcp
    server $cluster_id-worker-0  192.168.111.50:80 check
    server $cluster_id-worker-1  192.168.111.51:80 check
    server $cluster_id-worker-2  192.168.111.52:443 check

backend https-main
    balance source
    mode tcp
    server $cluster_id-worker-0  192.168.111.50:443 check
    server $cluster_id-worker-1  192.168.111.51:443 check
    server $cluster_id-worker-2  192.168.111.52:443 check
EOF
    echo "$cfg_file"
}

gen_build() {
    local out_dir="$1"
    local docker_file

    docker_file="$(realpath "$out_dir/Dockerfile")"

    mkdir -p "$out_dir"

    cat <<'EOF' >"$docker_file"
FROM haproxy:1.7
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

ENV HAPROXY_USER haproxy

EXPOSE 80
EXPOSE 443
EXPOSE 6443
EXPOSE 22623

RUN groupadd --system ${HAPROXY_USER} && \
useradd --system --gid ${HAPROXY_USER} ${HAPROXY_USER} && \
mkdir --parents /var/lib/${HAPROXY_USER} && \
chown -R ${HAPROXY_USER}:${HAPROXY_USER} /var/lib/${HAPROXY_USER}

CMD ["haproxy", "-db", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
EOF
    echo "$docker_file"
}

VERBOSE="false"
export VERBOSE

while getopts ":ho:s:m:v" opt; do
    case ${opt} in
    o)
        out_dir=$OPTARG
        ;;
    v)
        VERBOSE="true"
        ;;
    s)
        prep_host_setup_src=$OPTARG
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

if [ "$#" -ne 1 ]; then
    usage
fi

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi
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

out_dir=${out_dir:-$PROJECT_DIR/haproxy}
out_dir=$(realpath "$out_dir")

manifest_dir=${manifest_dir:-$PROJECT_DIR/cluster}
manifest_dir=$(realpath "$manifest_dir")

parse_manifests "$manifest_dir"

map_cluster_vars

COMMAND=$1
shift
case "$COMMAND" in
build)
    ofile=$(gen_config_haproxy "$out_dir")
    printf "Generated %s...\n" "$ofile"
    ofile=$(gen_build "$out_dir")
    printf "Generated %s...\n" "$ofile"
    printf "Building haproxy container...\n"
    if ! image_id=$(cd "$PROJECT_DIR"/haproxy && podman build . 2>/dev/null | rev | cut -d ' ' -f 1 | rev | tail -1); then
        printf "Error while building haproxy container...\n"
    fi
    printf "Tagging image %s with %s ...\n" "$image_id" "$HAPROXY_IMAGE_NAME:$HAPROXY_IMAGE_TAG"
    if ! podman tag "$image_id" "$HAPROXY_IMAGE_NAME:$HAPROXY_IMAGE_TAG"; then
        printf "Failed to tag image_id %s!" "$image_id"
    fi
    ;;
gen-config)
    ofile=$(gen_config_haproxy "$out_dir")
    printf "Generated %s...\n" "$ofile"
    ;;
start)
    if ! image_id=$(podman images | grep $HAPROXY_IMAGE_NAME | awk '{print $3}'); then
        printf "Cannot find image \"%s\", build first?\n" "$HAPROXY_IMAGE_NAME"
        exit 1
    fi
    if podman ps --all | grep "$HAPROXY_CONTAINTER_NAME" >/dev/null; then
        printf "Container already exists, removing and starting...\n"
        if ! podman stop "$HAPROXY_CONTAINTER_NAME" >/dev/null; then
            printf "Could not stop \"%s\"" "$HAPROXY_CONTAINTER_NAME"
            exit 1
        fi
        if ! podman rm "$HAPROXY_CONTAINTER_NAME" >/dev/null; then
            printf "Could not remove \"%s\"" "$HAPROXY_CONTAINTER_NAME"
            exit 1
        fi
    fi
    if ! cid=$(podman run -d --name "$HAPROXY_CONTAINTER_NAME" --net=host -p 80:80 -p 443:443 -p 6443:6443 -p 22623:22623 "$image_id" -f /usr/local/etc/haproxy/haproxy.cfg); then
        printf "Could not start haproxy container!"
        exit 1
    fi
    printf "Started container id %s\n" "$cid"
    ;;
stop)
    cid=$(podman stop "$HAPROXY_CONTAINTER_NAME") && printf "Stopped %s\n" "$cid"
    ;;
remove)
    podman stop "$HAPROXY_CONTAINTER_NAME" 2>/dev/null && podman rm "$HAPROXY_CONTAINTER_NAME" > /dev/null
    image_id=$(podman images | grep $HAPROXY_IMAGE_NAME | awk '{print $3}') && podman rmi "$image_id" > /dev/null
    ;;

*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
