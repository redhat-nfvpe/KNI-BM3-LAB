#!/bin/bash

# This script generates dnsmasq configuration files for the UPI install project.
# The UPI install project employs two instances of dnsmasq.  One instance provides
# dhcp/pxe boot for the provisioning network.  The second instance provides dhcp
# and DNS for the baremetal network.  Dnsmasq is run as a container using podman.
# The configuration files for both dnsmasqs are located as should below.
#
#── /root_path/
#│   ├── bm
#│   │   ├── etc
#│   │   │   └── dnsmasq.d
#│   │   │       ├── dnsmasq.conf
#│   │   │       └── dnsmasq.hostsfile
#│   │   └── var
#│   │       └── run
#│   │           ├── dnsmasq.leasefile
#│   │           └── dnsmasq.log
#│   └── prov
#│       ├── etc
#│       │   └── dnsmasq.conf
#│       └── var
#│           └── run
#│               ├── dnsmasq.leasefile
#│               └── dnsmasq.log
#
# This script requires a /root_path/ argument in order to set the proper locations
# in the generated config files.  For the provisioning network, only the dnsmasq.conf
# is generated.  The dnsmasq.leasefile and dnsmasq.logfile are created when dnsmasq
# is started.  For the the baremetal network, dnsmasq.conf and dnsmasq.hostsfiles are
# generated.
#
# The script also requires a path to one or three MASTER manifest files.
# The name: attribute should be master-0[, master-1, master-2].
#
# An example manifest file is show below.
#
# apiVersion: metalkube.org/v1alpha1
#
# kind: BareMetalHost
# metadata:
#   name: master-0
# spec:
#   externallyProvisioned: true
#   online: true # Must be set to true for provisioing
#   hardwareProfile: ""
#   bmc:
#     address: ipmi://10.19.110.16
#     credentialsName: ha-lab-ipmi-secret
#   bootMACAddress: 0c:c4:7a:8e:ee:0c

usage() {
    cat <<EOM
    Generate configuration files for either the provisioning interface or the
    baremetal interface. Files created:
       provisioning: dnsmasq.conf
       baremetal: dnsmasq.conf, dnsmasq.conf

    Usage:
     $(basename "$0") base_dir prov interface
     $(basename "$0") base_dir bm interface cluster_id cluster_domain

    base_dir   -- location of the base dir for the target config files
    prov|bm    -- prov,  generate for the provisioning network.
                  bm, generate for the baremetall network.
    interface  -- Interface for the provisioning network.
    cluster_id -- Name of the specific cluster instance. test1 in test1.tt.testing
    cluster_domain -- Domain of the cluster instance. tt.testing. in test1.tt.testing
EOM
    exit 0
}

gen_config_prov() {
    intf=$1
    out_dir=$2
    
    etc_dir="$out_dir/prov/etc/dnsmasq.d"
    var_dir="$out_dir/prov/var/run"
    
    mkdir -p "$etc_dir"
    mkdir -p "$var_dir"
    
cat <<EOF > "$etc_dir/dnsmasq.conf"
# This config file is intended for use with a container instance of dnsmasq

echo "The container should be run as follows with the generated dnsmasq.conf file"
echo "placed in $etc_dir/"
echo "log and leasefiles will be located in $var_dir/"
echo "# podman run -d --name dnsmasq-prov --net=host -v $var_dir:/var/run/dnsmasq:Z \\"
echo "#  -v $etc_dir:/etc/dnsmasq.d:Z \\"
echo "#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
echo "#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq \\
echo "#  --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"

port=0 # do not activate nameserver
interface=$intf
bind-interfaces

dhcp-range=172.22.0.11,172.22.0.30,30m

# do not send default gateway
dhcp-option=3
# do not send dns server
dhcp-option=6

# Legacy PXE
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:bios,undionly.kpxe

# UEFI
dhcp-match=set:efi32,option:client-arch,6
dhcp-boot=tag:efi32,ipxe.efi
dhcp-match=set:efibc,option:client-arch,7
dhcp-boot=tag:efibc,ipxe.efi
dhcp-match=set:efi64,option:client-arch,9
dhcp-boot=tag:efi64,ipxe.efi

# verbose
log-queries
log-dhcp

dhcp-leasefile=/var/run/dnsmasq/dnsmasq.leasefile
log-facility=/var/run/dnsmasq/dnsmasq.log

# iPXE - chainload to matchbox ipxe boot script
dhcp-userclass=set:ipxe,iPXE
dhcp-boot=tag:ipxe,http://172.22.0.10:8080/boot.ipxe

# Enable dnsmasq's built-in TFTP server
enable-tftp

# Set the root directory for files available via FTP.
tftp-root=/var/lib/tftpboot

tftp-no-blocksize

dhcp-boot=pxelinux.0

EOF
}

gen_hostfile_bm() {
    cluster_id=$1
    cluster_domain=$2
    
    
    # cluster_id.cluster_domain
    
    #list of master manifests
    
    # loop through list
    # make sure there is a master-0[, master-1, master-2]
    #
    # 52:54:00:82:68:3f,192.168.111.10,cluster_id-bootstrap.cluster_domain
    # 52:54:00:82:68:3f,192.168.111.11,cluster_id-master-0.cluster_domain
    # 52:54:00:82:68:3f,192.168.111.12,cluster_id-master-1.cluster_domain
    # 52:54:00:82:68:3f,192.168.111.13,cluster_id-master-2.cluster_domain
    #
    # 192.168.111.50,cluster_id-worker-0.cluster_domain
    # 192.168.111.51,cluster_id-worker-1.cluster_domain
    # ...
    # 192.168.111.59,cluster_id-worker-9.cluster_domain
    
}

gen_bm_help() {
    echo "# The container should be run as follows with the generated dnsmasq.conf file"
    echo "# located in $etc_dir/"
    echo "# an automatically generated dnsmasq hostsfile should also be present in"
    echo "# $etc_dir/"
    echo "#"
    echo "# podman run -d --name dnsmasq-bm --net=host\\"
    echo "#  -v $var_dir:/var/run/dnsmasq:Z \\"
    echo "#  -v $etc_dir:/etc/dnsmasq.d:Z \\"
    echo "#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
    echo "#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq \\"
    echo "#  --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"
}

gen_config_bm() {
    intf="$1"
    out_dir="$2"
    cluster_id="$3"
    cluster_domain="$4"
    
    etc_dir="$out_dir/bm/etc/dnsmasq.d"
    var_dir="$out_dir/bm/var/run/dnsmasq"
    
    mkdir -p "$etc_dir"
    mkdir -p "$var_dir"
    
    cat <<EOF > "$etc_dir/dnsmasq.conf"
# This config file is intended for use with a container instance of dnsmasq

$(gen_bm_help)
#-p, --port=<port>
# Listen on <port> instead of the standard DNS port (53). Setting this to zero completely disables DNS # function, leaving only DHCP and/or TFTP.
#port=0
interface=$intf
bind-interfaces

strict-order
except-interface=lo

domain=$cluster_domain,192.168.111.0/24

dhcp-range=192.168.111.10,192.168.111.60,30m
#default gateway
dhcp-option=3,192.168.111.1
#dns server
dhcp-option=6,192.168.111.1

log-queries
log-dhcp

dhcp-no-override
dhcp-authoritative

# -> $ORIGIN tt.testing.

auth-zone=bastion.$cluster_id.$cluster_domain,192.168.111.0/24
auth-server=bastion.$cluster_id.$cluster_domain,$intf
host-record=bastion.$cluster_id.$cluster_domain,192.168.111.1

# -> $TTL 10800      ; 3 hours
auth-ttl=10800

#    owner-name  ttl  class rr    name-server         email-addr
# -> @           3600 IN    SOA   bastion.test1.tt.testing. root.tt.testing. (
#                                   2019010101 ; serial
#                                   7200       ; refresh (2 hours)
#                                   3600       ; retry (1 hour)
#                                   1209600    ; expire (2 weeks)
#                                   3600       ; minimum (1 hour)
#                                   )
#auth-soa=<serial>[,<hostmaster>[,<refresh>[,<retry>[,<expiry>]]]]
auth-soa=2019010101,bastion.$cluster_id.$cluster_domain,7200,3600,1209600
# -> srvce.prot.owner-name                   ttl  class rr  pri weight port target
# -> _etcd-server-ssl._tcp.test1.tt.testing. 8640 IN    SRV 0   10     2380 etcd-0.test1.tt.testing.
#<name>,<target>,<port>,<priority>,<weight>
srv-host=_etcd-server-ssl._tcp.$cluster_id.$cluster_domain,etcd-0.$cluster_id.$cluster_domain,2380,0,10
srv-host=_etcd-server-ssl._tcp.$cluster_id.$cluster_domain,etcd-1.$cluster_id.$cluster_domain,2380,10,10
srv-host=_etcd-server-ssl._tcp.$cluster_id.$cluster_domain,etcd-2.$cluster_id.$cluster_domain,2380,10,10

host-record=lb,192.168.111.1
cname=api,lb
cname=api-int,lb

cname=apps,lb
cname=*.apps,lb

# -> api.test1.tt.testing.                        A 192.168.111.1
#address=/api.$cluster_id.$cluster_domain/192.168.111.1
# -> api-int.test1.tt.testing.                    A 192.168.111.1
#address=/api-in.$cluster_id.$cluster_domain/192.168.111.1

# -> test1-bootstrap.tt.testing.                  A 192.168.111.10
host-record=$cluster_id-bootstrap,192.168.111.1
#address=/$cluster_id-bootstrap.$cluster_domain/192.168.111.10

# -> test1-master-0.tt.testing.                   A 192.168.111.11
#address=/$cluster_id-master-0.$cluster_domain/192.168.111.11
host-record=$cluster_id-master-0, 192.168.111.11
# -> test1-master-1.tt.testing.                   A 192.168.111.12
#address=/$cluster_id-master-1.$cluster_domain/192.168.111.12
host-record=$cluster_id-master-1, 192.168.111.12
# -> test1-master-2.tt.testing.                   A 192.168.111.13
#address=/$cluster_id-master-2.$cluster_domain/192.168.111.13
host-record=$cluster_id-master-2, 192.168.111.13

# -> test1-worker-0.tt.testing.                   A 192.168.111.50
#address=/$cluster_id-worker-0.$cluster_domain/192.168.111.50
host-record=$cluster_id-worker-0, 192.168.111.50
# -> test1-worker-1.tt.testing.                   A 192.168.111.51
#address=/$cluster_id-worker-1.$cluster_domain/192.168.111.51
host-record=$cluster_id-master-0, 192.168.111.51

# -> etcd-0.test1.tt.testing.                     IN  CNAME test1-master-0.tt.testing.
cname="$cluster_id"-master-0."$cluster_domain",etcd-0."$cluster_id.$cluster_domain"

# -> $ORIGIN apps.test1.tt.testing.
# -> *                                                    A                192.168.111.1
#address=/.apps."$cluster_id.$cluster_domain"/192.168.111.1

#dhcp-hostsfile=/etc/dnsmasq.d/dnsmasq.hostsfile
dhcp-leasefile=/var/run/dnsmasq/dnsmasq.leasefile
log-facility=/var/run/dnsmasq/dnsmasq.log

EOF
}

if [ "$#" -lt 3 ]; then
    usage
fi

outdir=$(realpath "$1")
shift

command=$1
shift

DNSMASQ_RUN_DIR="var/run"
DNSMASQ_ETC_DIR="etc/dnsmasq.d"

case "$command" in
    prov)
        if [ "$#" -ne 1 ]; then
            usage
        fi
        
        intf="$1"
        gen_config_prov "$intf" "$outdir"
    ;;
    bm)
        if [ "$#" -ne 3 ]; then
            usage
        fi
        
        intf="$1"
        cluster_id="$2"
        cluster_domain="$3"
        gen_config_bm "$intf" "$outdir" "$cluster_id" "$cluster_domain"
    ;;
    *)
        echo "Unknown command: $command"
        usage
    ;;
esac

