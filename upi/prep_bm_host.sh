#!/bin/bash

#set -e

###------------------------------------------------###
### Need interface input from user via environment ###
###------------------------------------------------###

source prep_bm_host.src

printf "\nChecking parameters...\n\n"

for i in PROV_INTF PROV_BRIDGE BM_INTF BM_BRIDGE EXT_INTF PROV_IP_CIDR BM_IP_CIDR; do
    if [[ -z "${!i}" ]]; then
        echo "You must set PROV_INTF, PROV_BRIDGE, BM_INTF, BM_BRIDGE, EXT_INTF, PROV_IP_CIDR and BM_IP_CIDR as environment variables!"
        echo "Edit prep_bm_host.src to set these values."
        exit 1
    else
        echo $i": "${!i}
    fi
done

###------------------------------###
### Source helper scripts first! ###
###------------------------------###

# shellcheck disable=SC1091
source "scripts/network_conf.sh"
# shellcheck disable=SC1091
source "scripts/utils.sh"

###-------------------------------###
### Call gen_*.sh scripts second! ###
###-------------------------------###

./gen_dnsmasq.sh
./gen_haproxy.sh

###---------------------------------------------###
### Configure provisioning interface and bridge ###
###---------------------------------------------###

printf "\nConfiguring provisioning interface ($PROV_INTF) and bridge ($PROV_BRIDGE)...\n\n"

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$PROV_BRIDGE
TYPE=Bridge
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$PROV_BRIDGE
DEVICE=$PROV_BRIDGE
ONBOOT=yes
IPADDR=$(nthhost $PROV_IP_CIDR 10)
NETMASK=255.255.255.0
ZONE=public
EOF

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$PROV_INTF
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$PROV_INTF
DEVICE=$PROV_INTF
ONBOOT=yes
BRIDGE=$PROV_BRIDGE
EOF

ifdown $PROV_BRIDGE
ifup $PROV_BRIDGE

ifdown $PROV_INTF
ifup $PROV_INTF

###-------------------------------###
### Configure baremetal interface ###
###-------------------------------###

printf "\nConfiguring baremetal interface ($BM_INTF) and bridge ($BM_BRIDGE)...\n\n"

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE
TYPE=Bridge
NM_CONTROLLED=no
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=no
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
NAME=$BM_BRIDGE
DEVICE=$BM_BRIDGE
IPADDR=$(nthhost $BM_IP_CIDR 1)
NETMASK=255.255.255.0
ONBOOT=yes
EOF

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$BM_INTF
TYPE=Ethernet
NM_CONTROLLED=no
NAME=$BM_INTF
DEVICE=$BM_INTF
ONBOOT=yes
BRIDGE=$BM_BRIDGE
EOF

ifdown $BM_BRIDGE
ifup $BM_BRIDGE

ifdown $BM_INTF
ifup $BM_INTF

###-----------------------------###
### Create required directories ###
###-----------------------------###

# printf "\nCreating required directories...\n\n"

# if [[ ! -d "~/dev/test1" ]]; then
#     mkdir -p ~/dev/test1
#     mkdir -p ~/dev/upi-dnsmasq/$PROV_INTF
#     mkdir -p ~/dev/upi-dnsmasq/$BM_INTF
#     mkdir -p ~/dev/scripts
#     mkdir -p ~/dev/containers/haproxy
#     sudo mkdir -p /etc/matchbox
#     mkdir -p ~/.matchbox
#     sudo mkdir -p /var/lib/matchbox
#     sudo mkdir -p /etc/coredns
#     sudo mkdir -p /var/run/dnsmasq
#     sudo mkdir -p /var/run/dnsmasq2
#     mkdir -p ~/go/src
# fi

###--------------------------------------------------###
### Configure iptables to allow for external traffic ###
###--------------------------------------------------###

printf "\nConfiguring iptables to allow for external traffic...\n\n"

cat <<EOF > scripts/iptables.sh
#!/bin/bash

ins_del_rule()
{
    operation=\$1
    table=\$2
    rule=\$3
   
    if [ "\$operation" == "INSERT" ]; then
        if ! sudo iptables -t "\$table" -C \$rule > /dev/null 2>&1; then
            sudo iptables -t "\$table" -I \$rule
        fi
    elif [ "\$operation" == "DELETE" ]; then
        sudo iptables -t "\$table" -D \$rule
    else
        echo "\${FUNCNAME[0]}: Invalid operation: \$operation"
        exit 1
    fi
}

    #allow DNS/DHCP traffic to dnsmasq and coredns
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p udp -m udp --dport 67 -j ACCEPT"
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p udp -m udp --dport 53 -j ACCEPT"
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p tcp -m tcp --dport 67 -j ACCEPT"
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p tcp -m tcp --dport 53 -j ACCEPT"
   
    #enable routing from provisioning and cluster network to external
    ins_del_rule "INSERT" "nat" "POSTROUTING -o $EXT_INTF -j MASQUERADE"
    ins_del_rule "INSERT" "filter" "FORWARD -i $PROV_BRIDGE -o $EXT_INTF -j ACCEPT"
    ins_del_rule "INSERT" "filter" "FORWARD -o $PROV_BRIDGE -i $EXT_INTF -m state --state RELATED,ESTABLISHED -j ACCEPT"
    ins_del_rule "INSERT" "filter" "FORWARD -i $BM_BRIDGE -o $EXT_INTF -j ACCEPT"
    ins_del_rule "INSERT" "filter" "FORWARD -o $BM_BRIDGE -i $EXT_INTF -m state --state RELATED,ESTABLISHED -j ACCEPT"

    #remove certain problematic REJECT rules
    REJECT_RULE=\`iptables -S | grep "INPUT -j REJECT --reject-with icmp-host-prohibited"\`

    if [[ ! -z "\$REJECT_RULE" ]]; then
        iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited
    fi

    REJECT_RULE2=\`iptables -S | grep "FORWARD -j REJECT --reject-with icmp-host-prohibited"\`

    if [[ ! -z "\$REJECT_RULE2" ]]; then
        iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
    fi
EOF

pushd scripts
chmod 755 iptables.sh
./iptables.sh
popd

###------------------------------------------------------###
### Install Git, Podman, Unzip, Ipmitool, Dnsmasq and Yq ###
###------------------------------------------------------###

printf "\nInstalling dependencies via yum...\n\n"

sudo yum install -y git podman unzip ipmitool dnsmasq yq

###----------------###
### Install Golang ###
###----------------###

printf "\nInstalling Golang...\n\n"

export GOROOT=/usr/local/go
export GOPATH=$HOME/go/src
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

if [[ ! -d "/usr/local/go" ]]; then
    pushd /tmp
    curl -O https://dl.google.com/go/go1.12.6.linux-amd64.tar.gz
    tar -xzf go1.12.6.linux-amd64.tar.gz
    sudo mv go /usr/local
    # TODO: Use sed instead below?
    echo "export GOROOT=/usr/local/go" >> ~/.bash_profile
    echo "export GOPATH=$HOME/go/src" >> ~/.bash_profile
    echo "export PATH=$GOPATH/bin:$GOROOT/bin:$PATH" >> ~/.bash_profile
    popd
fi

###-----------------------------------###
### Set up NetworkManager DNS overlay ###
###-----------------------------------###

printf "\nSetting up NetworkManager DNS overlay...\n\n"

DNSCONF=/etc/NetworkManager/conf.d/openshift.conf
DNSCHANGED=""
if ! [ -f "${DNSCONF}" ]; then
    echo -e "[main]\ndns=dnsmasq" | sudo tee "${DNSCONF}"
    DNSCHANGED=1
fi
DNSMASQCONF=/etc/NetworkManager/dnsmasq.d/openshift.conf
if ! [ -f "${DNSMASQCONF}" ]; then
    echo server=/tt.testing/192.168.111.1 | sudo tee "${DNSMASQCONF}"
    DNSCHANGED=1
fi
if [ -n "$DNSCHANGED" ]; then
    sudo systemctl restart NetworkManager
fi

###-----------------###
### Set up tftpboot ###
###-----------------###

# TODO: This might be unnecessary, as the dnsmasq container images we
#       are using are rumored to self-contain this
printf "\nSetting up tftpboot...\n\n"

if [[ ! -d "/var/lib/tftpboot" ]]; then
    mkdir -p /var/lib/tftpboot
    pushd /var/lib/tftpboot
    curl -O http://boot.ipxe.org/ipxe.efi
    curl -O http://boot.ipxe.org/undionly.kpxe
    popd
fi

###-----------------------------------------###
### Create HAProxy configuration and assets ###
###-----------------------------------------###

# TODO: Check if image is already built, or pre-build it elsewhere
#       and remove this section completely
printf "\nConfiguring HAProxy and building container image...\n\n"

HAPROXY_IMAGE_ID=`podman images | grep akraino-haproxy | awk {'print $3'}`

if [[ -z "$HAPROXY_IMAGE_ID" ]]; then
    pushd haproxy

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
    server test1-bootstrap $(nthhost $BM_IP_CIDR 10):6443 check
    server test1-master-0  $(nthhost $BM_IP_CIDR 11):6443 check

backend mcs-main
    balance source
    mode tcp
    server test1-bootstrap $(nthhost $BM_IP_CIDR 10):22623 check
    server test1-master-0  $(nthhost $BM_IP_CIDR 11):22623 check

backend http-main
    balance source
    mode tcp
    server test1-worker-0  $(nthhost $BM_IP_CIDR 50):80 check

backend https-main
    balance source
    mode tcp
    server test1-worker-0  $(nthhost $BM_IP_CIDR 50):443 check
EOF

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

    HAPROXY_IMAGE_ID=`podman build . | rev | cut -d ' ' -f 1 | rev | tail -1`
    podman tag $HAPROXY_IMAGE_ID akraino-haproxy:latest
    popd
fi

###-------------------------###
### Start HAProxy container ###
###-------------------------###

# TODO: Check if container is already running
printf "\nStarting HAProxy container...\n\n"

HAPROXY_CONTAINER=`podman ps | grep haproxy`

if [[ -z "$HAPROXY_CONTAINER" ]]; then
    podman run -d --name haproxy --net=host -p 80:80 -p 443:443 -p 6443:6443 -p 22623:22623 $HAPROXY_IMAGE_ID -f /usr/local/etc/haproxy/haproxy.cfg
fi

###--------------------------------------###
### Start provisioning dnsmasq container ###
###--------------------------------------###

printf "\nStarting provisioning dnsmasq container...\n\n"

DNSMASQ_PROV_CONTAINER=`podman ps | grep dnsmasq-prov`

if [[ -z "$DNSMASQ_PROV_CONTAINER" ]]; then
    podman run -d --name dnsmasq-prov --net=host -v dnsmasq/prov/var/run:/var/run/dnsmasq:Z \
    -v dnsmasq/prov/etc/dnsmasq.d:/etc/dnsmasq.d:Z \
    --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \
    --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q
fi

###-----------------------------------###
### Start baremetal dnsmasq container ###
###-----------------------------------###

printf "\nStarting baremetal dnsmasq container...\n\n"

DNSMASQ_BM_CONTAINER=`podman ps | grep dnsmasq-bm`

if [[ -z "$DNSMASQ_BM_CONTAINER" ]]; then
    podman run -d --name dnsmasq-bm --net=host -v dnsmasq/bm/var/run:/var/run/dnsmasq:Z \
    -v dnsmasq/bm/etc/dnsmasq.d:/etc/dnsmasq.d:Z \
    --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \
    --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q
fi

###--------------------###
### Configure matchbox ###
###--------------------###

printf "\nConfiguring matchbox...\n\n"

pushd matchbox

if [[ ! -d "matchbox" ]]; then
    git clone https://github.com/poseidon/matchbox.git
    pushd matchbox/scripts/tls
    export SAN=IP.1:$(nthhost $PROV_IP_CIDR 10)
    ./cert-gen
    sudo cp ca.crt server.crt server.key /etc/matchbox
    cp ca.crt client.crt client.key ~/.matchbox 
    popd
fi

popd

# TODO: Have this use the same "matchbox" directory as above?
if [[ ! -d "/var/lib/matchbox/assets" ]]; then
    sudo mkdir /var/lib/matchbox/assets
    pushd /var/lib/matchbox/assets
    curl -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/4.1.0/rhcos-4.1.0-x86_64-installer-initramfs.img
    curl -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/4.1.0/rhcos-4.1.0-x86_64-installer-kernel
    curl -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/4.1.0/rhcos-4.1.0-x86_64-metal-bios.raw.gz
    curl -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/4.1.0/rhcos-4.1.0-x86_64-metal-uefi.raw.gz
    popd
fi

###--------------------------###
### Start matchbox container ###
###--------------------------###

printf "\nStarting matchbox container...\n\n"

MATCHBOX_CONTAINER=`podman ps | grep matchbox`

if [[ -z "$MATCHBOX_CONTAINER" ]]; then
    podman run -d --net=host --name matchbox -v /var/lib/matchbox:/var/lib/matchbox:Z -v /etc/matchbox:/etc/matchbox:Z,ro quay.io/poseidon/matchbox:latest -address=0.0.0.0:8080 -rpc-address=0.0.0.0:8081 -log-level=debug
fi

###----------------------------------------###
### Configure coredns Corefile and db file ###
###----------------------------------------###

printf "\nConfiguring CoreDNS...\n\n"

if [[ ! -f "coredns/Corefile" ]]; then
cat <<EOF > coredns/Corefile
.:53 {
    log
    errors
    forward . 10.11.5.19
}

tt.testing:53 {
    log
    errors
    file /etc/coredns/db.tt.testing
    debug
}

EOF

cat <<'EOF' > coredns/db.tt.testing
$ORIGIN tt.testing.
$TTL 10800      ; 3 hours
@       3600 IN SOA sns.dns.icann.org. noc.dns.icann.org. (
                                2019010101 ; serial
                                7200       ; refresh (2 hours)
                                3600       ; retry (1 hour)
                                1209600    ; expire (2 weeks)
                                3600       ; minimum (1 hour)
                                )

_etcd-server-ssl._tcp.test1.tt.testing. 8640 IN    SRV 0 10 2380 etcd-0.test1.tt.testing.

api.test1.tt.testing.                        A $(nthhost $BM_IP_CIDR 1)
api-int.test1.tt.testing.                    A $(nthhost $BM_IP_CIDR 1)
test1-master-0.tt.testing.                   A $(nthhost $BM_IP_CIDR 11)
test1-worker-0.tt.testing.                   A $(nthhost $BM_IP_CIDR 50)
test1-bootstrap.tt.testing.                  A $(nthhost $BM_IP_CIDR 10)
etcd-0.test1.tt.testing.                     IN  CNAME test1-master-0.tt.testing.

$ORIGIN apps.test1.tt.testing.
*                                                    A                $(nthhost $BM_IP_CIDR 1)
EOF
fi

###-------------------------###
### Start coredns container ###
###-------------------------###

printf "\nStarting CoreDNS container...\n\n"

COREDNS_CONTAINER=`podman ps | grep coredns`

if [[ -z "$COREDNS_CONTAINER" ]]; then
    podman run -d --expose=53 --expose=53/udp -p $(nthhost $BM_IP_CIDR 1):53:53 -p $(nthhost $BM_IP_CIDR 1):53:53/udp \
    -v coredns:/etc/coredns:z --name coredns coredns/coredns:latest -conf /etc/coredns/Corefile
fi

###----------------------------###
### Prepare OpenShift binaries ###
###----------------------------###

printf "\nInstalling OpenShift binaries...\n\n"

pushd /tmp

if [[ ! -f "/usr/local/bin/openshift-install" ]]; then
    # TODO: These versions change without warning!  Need to accomodate for this.
    curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux-4.1.4.tar.gz
    tar xvf openshift-install-linux-4.1.4.tar.gz
    sudo mv openshift-install /usr/local/bin/
    curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux-4.1.4.tar.gz
    tar xvf openshift-client-linux-4.1.4.tar.gz
    sudo mv oc /usr/local/bin/
fi

###-------------------###
### Prepare terraform ###
###-------------------###

printf "\nInstalling Terraform...\n\n"

if [[ ! -f "/usr/bin/terraform" ]]; then
    curl -O https://releases.hashicorp.com/terraform/0.12.2/terraform_0.12.2_linux_amd64.zip
    unzip terraform_0.12.2_linux_amd64.zip
    sudo mv terraform /usr/bin/.
    git clone https://github.com/poseidon/terraform-provider-matchbox.git
    cd terraform-provider-matchbox
    go build
    mkdir -p ~/.terraform.d/plugins
    cp terraform-provider-matchbox ~/.terraform.d/plugins/.
fi

popd

printf "\nDONE\n"
