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

### Onedata related variables
# The public DNS zone to be created in OTC. There should be a registred domain of
# the same name under your control. The domain should use the following nameservers:
#   - ns1.open-telekom-cloud.com
#   - ns2.open-telekom-cloud.com
variable "dnszone" {
#  default = ""
}

# A valid email will be needed when creating cerificates
variable "email" {
#  default = ""
}

variable "public_key_file" {
  default = "/home/ubuntu/.ssh/id_rsa.pub"
}

# The onezone managing your space  - the one which is going to be supported by the
# oneprovider 
variable "onezone" {
  default = "https://onedata.hnsc.otc-service.com"
}

### The following variables can optionally be set. Reasonable defaults are provided.

### Ceph cluster settings
# This is the number of management nodes. It should be 1.
variable "ceph-mgt_count" {
  default = "1"
}

# The number of monitors of Ceph cluster. 
variable "ceph-mon_count" {
  default = "1"
}

# The number of VM for running OSDs.
variable "ceph-osd_count" {
  default = "3"
}

### VM (Instance) Settings
# The flavor name used for Ceph monitors and OSDs. 
variable "flavor_name" {
  default = "h2.3xlarge.10"
}

# The image name used for all instances
variable "image_name" {
  default = "Standard_CentOS_7_133_20171122_0"
}

# Availability zone 
variable "availability_zone" {
  default = "eu-de-01"
}

# The size of elastic volumes which will be attached to the OSDs. The size is given in GB.
variable "vol_size" {
  default = "100"
}

# The type volume. It specifies the performance of a volume. "SSD" maps to "Ultra High I/O".
variable "vol_type" {
  default = "co-p1"
}

# The number of disks to attach to each VM for running OSDs. The raw Ceph total capacity
# will be (osd_count * disks-per-osd_count * vol_size) GB.
variable "disks-per-osd_count" {
  default = "0"
}

variable "image_vol_size" {
  default = "16"
}

variable "image_vol_type" {
  default = "SSD"
}

variable "image_uuid" {
  # Standard_CentOS_7_133_20171122_0
  default = "03027462-e23e-4f42-8447-e6ce8d56e8f4"
}

# The number of client VMs
variable "client_count" {
  default = "0"
}

# The flavor for clients
variable "client_flavor_name" {
  default = "h1.large.4"
}

# The number of oneprovider nodes
variable "provider_count" {
  default = "0"
}

# The flavor for provider nodes
variable "provider_flavor_name" {
  default = "h1.xlarge.4"
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

variable "sources_list_dest" {
  default = "/dev/null"
#  default = "/etc/apt/sources.list"   # Use this if OTC debmirror has problems
}

variable "storage_type" {
#  default = "posix"    # the data in the Ceph cluster are accessed via CephFS
  default = "ceph"    # the data in the Ceph cluster are accessed natively via rados
}

variable "oneclient_opts" {
  default = "--force-direct-io"
}

# The disk device naming (prefix) for the given flavor.
variable "vol_prefix" {
#  default = "/dev/xvd"
  #  default = "/dev/vd"
  default = "/dev/nvme"
}

