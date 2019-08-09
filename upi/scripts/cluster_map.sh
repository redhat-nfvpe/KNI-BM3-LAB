#!/bin/bash

DEFAULT_INITRD="assets/rhcos-4.1.0-x86_64-installer-initramfs.img"
DEFAULT_KERNEL="assets/rhcos-4.1.0-x86_64-installer-kernel"

declare -A CLUSTER_MAP=(
    [bootstrap_ign_file]="==./ocp/bootstrap.ign"
    [master_ign_file]="==./ocp/master.ign"
    [matchbox_client_cert]="==./matchbox/scripts/tls/client.crt"
    [matchbox_client_key]="==./matchbox/scripts/tls/client.key"
    [matchbox_trusted_ca_cert]="==./matchbox/scripts/tls/ca.crt"
    [matchbox_http_endpoint]="==http://${PROV_IP_ADDR}:8080"
    [matchbox_rpc_endpoint]="==${PROV_IP_ADDR}:8081"
    [pxe_initrd_url]="==$DEFAULT_INITRD"
    [pxe_kernel_url]="==$DEFAULT_KERNEL"
    [pxe_os_image_url]="==http://${PROV_IP_ADDR}:8080/assets/rhcos-4.1.0-x86_64-metal-bios.raw.gz"
    [bootstrap_public_ipv4]="==${BM_IP_BOOTSTRAP}"
    [bootstrap_ipmi_host]="%bootstrap.spec.bmc.address"
    [bootstrap_ipmi_user]="%bootstrap.spec.bmc.[credentialsName].stringdata.username@"
    [bootstrap_ipmi_pass]="%bootstrap.spec.bmc.[credentialsName].stringdata.password@"
    [bootstrap_mac_address]="%bootstrap.spec.bootMACAddress"
    [bootstrap_sdn_mac_address]="%bootstrap.metadata.annotations.kni.io\/sdnNetworkMac"
    [bootstrap_memory_gb]="==12"
    [bootstrap_vcpu]="==6"
    [bootstrap_provisioning_bridge]="==$PROV_BRIDGE"
    [bootstrap_baremetal_bridge]="==$BM_BRIDGE"
    [bootstrap_install_dev]="==vda"
    [nameserver]="==${BM_IP_NS}"
    [cluster_id]="%install-config.metadata.name"
    [cluster_domain]="%install-config.baseDomain"
    [provisioning_interface]="==${PROV_BRIDGE}"
    [baremetal_interface]="==${BM_BRIDGE}"
    [master_count]="%install-config.controlPlane.replicas"
)
export CLUSTER_MAP

declare -A CLUSTER_MASTER_MAP=(
    [master-\\1.spec.public_ipv4]="%master-([012]+).metadata.annotations.kni.io\/sdnIPv4"
    [master-\\1.spec.public_mac]="%master-([012]+).metadata.annotations.kni.io\/sdnNetworkMac"
    [master-\\1.metadata.ns]="=master-([012]+).metadata.name=$BM_IP_NS"
    [master-\\1.metadata.name]="%master-([012]+).metadata.name"
    [master-\\1.spec.bmc.address]="%master-([012]+).spec.bmc.address"
    [master-\\1.spec.bmc.user]="%master-([012]+).spec.bmc.[credentialsName].stringdata.username@"
    [master-\\1.spec.bmc.password]="%master-([012]+).spec.bmc.[credentialsName].stringdata.password@"
    [master-\\1.spec.bootMACAddress]="%master-([012]+).spec.bootMACAddress"
)
export CLUSTER_MASTER_MAP


declare -A WORKER_MAP=(
    [matchbox_client_cert]="==./matchbox/scripts/tls/client.crt"
    [matchbox_client_key]="==./matchbox/scripts/tls/client.key"
    [matchbox_trusted_ca_cert]="==./matchbox/scripts/tls/ca.crt"
    [matchbox_http_endpoint]="==http://${PROV_IP_ADDR}:8080"
    [matchbox_rpc_endpoint]="==${PROV_IP_ADDR}:8081"
    [pxe_initrd_url]="==assets/rhel_initrd.img"
    [pxe_kernel_url]="==assets/rhel_vmlinuz"
    [worker_kickstart]="==http:\/\/${PROV_IP_ADDR}:8080\/assets\/centos-rt-worker-kickstart.cfg"
    [cluster_id]="%install-config.metadata.name"
    [cluster_domain]="%install-config.baseDomain"
    [provisioning_interface]="==${PROV_INTF}"
    [baremetal_interface]="==${BM_INTF}"
    [worker_count]="%install-config.compute.0.replicas"
)
export WORKER_MAP

declare -A CLUSTER_WORKER_MAP=(
    [worker-\\1.metadata.ns]="=worker-([012]+).metadata.name=$BM_IP_NS"
    [worker-\\1.metadata.name]="%worker-([012]+).metadata.name"
    [master-\\1.public_ipv4]="%worker-([012]+).metadata.annotations.kni.io\/sdnIPv4"
    [worker-\\1.spec.bmc.address]="%worker-([012]+).spec.bmc.address"
    [worker-\\1.spec.bmc.user]="%worker-([012]+).spec.bmc.[credentialsName].stringdata.username@"
    [worker-\\1.spec.bmc.password]="%worker-([012]+).spec.bmc.[credentialsName].stringdata.password@"
    [worker-\\1.spec.bootMACAddress]="%worker-([012]+).spec.bootMACAddress"
)
export CLUSTER_WORKER_MAP