
# Project

This collection of scripts and config files prepare a provisioning host for a
baremetal OCP4.x cluster.  The cluster is provisioned using the Metal<sup>3</sup>
dev-scripts project.

# General Usage

- Clone [Akraino-kni-lab](https://github.com/atyronesmith/kni-lab.git)
- Clone [Metal<sup>3</sup>](<https://github.com/openshift-metal3/dev-scripts]>)
- Inside the Akraino-kni-lab project
  - Copy / Edit config_example.sh to match lab needs
  - Copy / Edit config_lab.sh to match lab needs
- export the PULL_SECRET env var as defined in Metal<sup>3<sup>
- export CONFIG=(location of config_example.sh -- full path )
- Run ./setup_prov.sh setup config_example.sh
- cd to Metal3 project
- run make
  
# Metal<sup>3</sup> Config File

The config_example.sh file contains an example of the variables that can be set to define operation of the cluster.  

- export PRO_IF="eno2"
  
    Define the **Provisioning** network interface

- export INT_IF="ens1f0"
  
    Define the **Baremetal** network inteface

- export MANAGE_INT_BRIDGE=n
  
    Don't allow Metal<sup>3</sup> to manage the ***Baremetal** bridge / network

- export ROOT_DISK="/dev/sda"
  
    Select the disk to use for the **Master** nodes root partition

- export CLUSTER_NAME="test1"
  
    Set the name of the cluster

- export BASE_DOMAIN="kni.home"
  
    Set the name of the cluster domain

- export MANAGE_BR_BRIDGE=n
  
    Don't allow Metal<sup>3</sup> manage the integration bridge

- export NODES_PLATFORM=BM

    Select baremetal install for Metal<sup>3</sup>

# Lab Config File

The following section defines the variables that can / should be defined
in the Lab Config file.

- export EXTERNAL_INTERFACE="eno1"

      Define the host interface with connectivity to the *Internet*

- export BM_BRIDGE="baremetal"
  
      Name of the **Baremetal** bridge (Should probably be baremetal)

- export BM_BRIDGE_CIDR="192.168.111.0/24"

    CIDR to be used for the **Baremetal** bridge

- export BM_BRIDGE_DHCP_START_OFFSET=20

    Starting address offset for nodes allocated by Metal<sup>3</sump>.  For example,
    with a 3 master deploy, the first master address would be 192.168.111.20.

- export BM_BRIDGE_DHCP_END_OFFSET=60

    Last address offset

- export BM_BRIDGE_NETMASK="255.255.255.0"
  
    Netmask to match the CIDR
