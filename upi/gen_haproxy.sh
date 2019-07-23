#!/bin/bash

usage() {
    cat <<EOM
    Usage:
    $(basename "$0") prov|bm interface

    prov|bm   -- prov,  generate for the provisioning network.
                 bm, generate for the baremetall network.
    interface -- Interface for the provisioning network.
EOM
    exit 0
}

gen_config_haproxy() {
    cluster_id=$1
    
cat <<EOF > haproxy.cfg
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
}

gen_build() {
cat <<'EOF' > Dockerfile
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
    
}



if [ "$#" -ne 2 ]; then
    usage
fi

COMMAND=$1
shift

DNSMASQ_RUN_DIR="var/run/dnsmasq"
DNSMASQ_ETC_DIR="etc/dnsmasq.d"

case "$COMMAND" in
    prov)
        DNSMASQ_REPO_DIR="dnsmasq/prov"
        gen_config_prov "$1"
    ;;
    bm)
        DNSMASQ_REPO_DIR="dnsmasq/bm"
        gen_config_bm "$1"
    ;;
    *)
        echo "Unknown command: ${COMMAND}"
        usage
    ;;
esac

