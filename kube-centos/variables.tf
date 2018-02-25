### OpenStack Credentials
variable "otc_username" {}

variable "otc_password" {}

variable "otc_domain_name" {}

### Project Settings
# The name of the project. It is used to prefix VM names. It should be unique among
# OTC as it is used to create names of VMs. 
variable "project" {
#   default = "od"
}

# Kube cidr for services - the default is 10.233.0.0/18
variable "kube_service_addresses" {}

# Kube cidr for pods - the default is 10.233.64.0/18
variable "kube_pods_subnet" {}

# VPN server network - the default in the config file is 10.8.0.0
variable "vpn_network" {}

variable "vpc_subnet" {
  default = "192.168.7.0/24"
}

variable "public_key_file" {
  default = "/home/ubuntu/.ssh/id_rsa.pub"
}

### Onedata related variables
# The public DNS zone to be created in OTC. There should be a registred domain of
# the same name under your control. The domain should use the following nameservers:
#   - ns1.open-telekom-cloud.com
#   - ns2.open-telekom-cloud.com
variable "dnszone" {
#  default = ""
}

variable "email" {
#  default = ""
}

### The following variables can optionally be set. Reasonable defaults are provided.

### Ceph cluster settings
# This is the number of contoller nodes. It should be 1.
variable "kube-ctlr_count" {
  default = "1"
}

# The number of workers of Kube cluster. 
variable "kube-work_count" {
  default = "3"
}

### VM (Instance) Settings
# The flavor name used for Ceph monitors and OSDs. 
variable "vpn_flavor_name" {
  default = "h1.large.4"
}

variable "ctlr_flavor_name" {
  default = "h2.3xlarge.10"
}

variable "work_flavor_name" {
  default = "h2.3xlarge.10"
}

# The image name used for all instances
variable "vpn_image_name" {
  default = "Community_Ubuntu_16.04_TSI_20171116_0"
}

variable "image_uuid" {
  # Standard_CentOS_7_133_20171122_0
  default = "03027462-e23e-4f42-8447-e6ce8d56e8f4"
}

variable "image_vol_size" {
  default = "16"
}

variable "image_vol_type" {
  default = "SSD"
}

# Availability zone 
variable "availability_zone" {
  default = "eu-de-01"
}

### OTC Specific Settings
variable "otc_tenant_name" {
  default = "eu-de"
}

variable "endpoint" {
  default = "https://iam.eu-de.otc.t-systems.com:443/v3"
}

variable "external_network" {
  default = "admin_external_net"
}

#### Internal usage variables ####
# The user name for loging into the VMs.
variable "ssh_user_name" {
  default = "linux"
}

variable "vpn_user_name" {
  default = "ubuntu"
}

variable "sources_list_dest" {
  default = "/dev/null"
#  default = "/etc/apt/sources.list"   # Use this if OTC debmirror has problems
}

