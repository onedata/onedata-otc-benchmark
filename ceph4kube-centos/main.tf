data "openstack_networking_subnet_v2" "subnet" {
  name = "${var.project}-subnet"
}

data "openstack_networking_network_v2" "network" {
  name = "${var.project}-network"
}

# data "template_file" "mgt_ip" {
#   template = "$${mgt_ip}"
#   vars {
#     mgt_ip = "${openstack_networking_floatingip_v2.ceph-mgt.address}"
#   }
# }

data "openstack_dns_zone_v2" "dnszone" {
  name = "${var.dnszone}"
}

resource "openstack_dns_recordset_v2" "ceph-mons" {
  depends_on = ["null_resource.provision-mgt"]
  #count   = "${var.ceph-mon_count}"
  zone_id = "${data.openstack_dns_zone_v2.dnszone.id}"
  name    = "${var.project}-ceph-mon.${var.dnszone}."
  type    = "A"
  # records = ["${openstack_compute_instance_v2.ceph-mons.*.access_ip_v4}"]
  records = ["${split("\n", trimspace(file("mon_ips")))}"]
}

resource "openstack_networking_floatingip_v2" "ceph-mons" {
  depends_on = ["openstack_compute_instance_v2.ceph-mons"]
  port_id  = "${element(openstack_networking_port_v2.mons-port.*.id, count.index)}"
  count = "${var.ceph-mon_count}"
  pool  = "${var.external_network}"
}

resource "openstack_blockstorage_volume_v2" "ceph-mon-image-vols" {
  count           = "${var.ceph-mon_count}"
  name = "${var.project}-${format("vol-%03d", count.index + 1)}"
  size = "${var.image_vol_size}"
  volume_type = "${var.image_vol_type}"
  availability_zone = "${var.availability_zone}"
  image_id = "${var.image_uuid}"
}

resource "openstack_compute_instance_v2" "ceph-mons" {
  count           = "${var.ceph-mon_count}"
  name            = "${var.project}-ceph-mon-${format("%02d", count.index+1)}"
  image_name      = "${var.image_name}"				#"bitnami-ceph-osdstack-7.0.22-1-linux-centos-7-x86_64-mp"
  flavor_name     = "${var.flavor_name}"
  key_pair        = "${openstack_compute_keypair_v2.otc.name}"
  availability_zone = "${var.availability_zone}"
  security_groups = [
    "${openstack_compute_secgroup_v2.secgrp_ceph.name}"
  ]
  network {
    port = "${element(openstack_networking_port_v2.mons-port.*.id, count.index)}"
    access_network = true
  }
  block_device {
    uuid                  = "${element(openstack_blockstorage_volume_v2.ceph-mon-image-vols.*.id, count.index)}"
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
  lifecycle {
    prevent_destroy = false
    create_before_destroy = true
  }
}

resource "openstack_networking_port_v2" "mons-port" {
  count              = "${var.ceph-mon_count}"
  network_id         = "${data.openstack_networking_network_v2.network.id}"
  security_group_ids = [
    "${openstack_compute_secgroup_v2.secgrp_ceph.id}",
  ]
  admin_state_up     = "true"
  fixed_ip           = {
    subnet_id        = "${data.openstack_networking_subnet_v2.subnet.id}"
  }
}

resource "null_resource" "provision-osd" {
  count = "${var.ceph-osd_count}"
  connection {
    bastion_host = "${var.project}-kube-ctlr.${var.dnszone}"
    host     = "${element(openstack_compute_instance_v2.ceph-osds.*.access_ip_v4, count.index)}"
    user     = "${var.ssh_user_name}"
    agent = true
    timeout = "600s"
  }
  # provisioner "file" {
  #   source = "etc/sources.list"
  #   destination = "sources.list"
  # }
  provisioner "remote-exec" {
    inline = [
      # "sudo cp sources.list ${var.sources_list_dest}", # if debmirror at #      "sudo apt-add-repository -y 'deb http://nova.clouds.archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse'", # if debmirror at OTC is not working
      "echo Instaling python ... not needed for CentOS",
      # "sudo apt-get -y update",
      # "sudo apt-get -y install python",
    ]
  }
  provisioner "remote-exec" {
    when = "destroy"
    on_failure = "continue"
    inline = [
      "echo Halting...",
      "sudo halt -p",
    ]
  }
}

resource "null_resource" "provision-mon" {
  count = "${var.ceph-mon_count}"
  depends_on = ["openstack_networking_floatingip_v2.ceph-mons"]
  connection {
    host     = "${element(openstack_networking_floatingip_v2.ceph-mons.*.address, count.index)}"
    user     = "${var.ssh_user_name}"
    #    private_key = "${file(var.ssh_key_file)}"
    agent = true
    timeout = "10m"
  }
  # provisioner "file" {
  #   source = "etc/sources.list"
  #   destination = "sources.list"
  # }
  provisioner "remote-exec" {
    inline = [
      "echo Connected ....",
      # "sudo cp sources.list ${var.sources_list_dest}", # if debmirror at #      "sudo apt-add-repository -y 'deb http://nova.clouds.archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse'", # if debmirror at OTC is not working
      # "sudo apt-get -y update",
      # "sudo apt-get -y install python",
    ]
  }
}

resource "null_resource" "provision-mgt" {
  depends_on = ["null_resource.provision-osd","null_resource.provision-mon","openstack_compute_volume_attach_v2.vas",]
  provisioner "local-exec" {
    command = "./local-setup.sh ${var.project} ${var.ceph-mon_count} ${var.ceph-osd_count} ${var.client_count} ${var.provider_count} ${var.dnszone}"
  }
  # provisioner "local-exec" {
  #   command = "echo ${openstack_networking_floatingip_v2.ceph-mgt.address} > MGT_IP"
  # }
  # triggers {
  #   cluster_instance_ids = "${join(",", openstack_networking_floatingip_v2.ceph-mgt.*.address)}"
  # }
  connection {
#      host     = "${openstack_networking_floatingip_v2.ceph-mgt.address}"
      host     = "${var.project}-kube-ctlr.${var.dnszone}"
      user     = "${var.ssh_user_name}"
      agent = true
  }
  provisioner "file" {
    source = "playbooks.tgz"
    destination = "playbooks.tgz"
  }
  provisioner "file" {
    content = "\n# Ceph nodes\n${join("\n", formatlist("%s %s", openstack_compute_instance_v2.ceph-osds.*.access_ip_v4, openstack_compute_instance_v2.ceph-osds.*.name))}\n${join("\n", formatlist("%s %s", openstack_compute_instance_v2.ceph-mons.*.access_ip_v4, openstack_compute_instance_v2.ceph-mons.*.name))}\n"
    destination = "hosts.tmp"
  }
  provisioner "file" {
    source = "etc.tgz"
    destination = "etc.tgz"
  }
  provisioner "remote-exec" {
    inline = [
      #      "chmod 600 .ssh/id_rsa",
      "sudo sed -i 's/[0-9.]* .*-ceph-.*//' /etc/hosts",
      "sudo sh -c 'cat hosts.tmp >> /etc/hosts'",
      "tar zxvf playbooks.tgz",
      "tar zxvf etc.tgz",
      # "sudo cp etc/sources.list ${var.sources_list_dest}", # if debmirror at OTC is not working
      # "sudo apt-get -y update",
#      "sudo apt-add-repository -y 'deb http://nova.clouds.archive.ubuntu.com/ubuntu/ xenial main restricted universe multiverse'", # if debmirror at OTC is not working
      # "sudo apt-get -y install software-properties-common",
      # "sudo apt-add-repository -y ppa:ansible/ansible",
      # "sudo apt-get -y update",
      # "sudo apt-get -y install ansible",
      "sudo cp etc/ansible-hosts inventory-ceph.ini",
      "sudo cp etc/ssh_config /etc/ssh/ssh_config",
#      "ansible-playbook -i inventory.ini playbooks/kube-ceph/kube-ceph-clean.yml -f 50 -T 30", 
#      "ansible-playbook -i inventory-ceph.ini playbooks/myceph/myceph-clean.yml -f 50 -T 30", 
      "ansible-playbook -i inventory-ceph.ini playbooks/myceph/ib-hosts-ceph.yml -f 50 -T 30", 
      "ansible-playbook playbooks/myceph/myceph.yml -i inventory-ceph.ini --extra-vars \"osd_disks=${var.disks-per-osd_count} vol_prefix=${var.vol_prefix}\" -f 50 -T 30",
      #"ansible-playbook -i inventory.ini playbooks/kube-ceph/kube-ceph.yml -e project=${var.project} -e dnszone=${var.dnszone} -f 50 -T 30", 
#      "ansible-playbook playbooks/oneprovider.yml --extra-vars \"domain=${var.dnszone} email=${var.email} onezone=${var.onezone} token=${var.support_token} storage_type=${var.storage_type}\"",
#      "ansible-playbook playbooks/oneclient.yml --extra-vars \"atoken=${var.access_token} oneclient_opts=${var.oneclient_opts}\"",
#      "ansible-playbook playbooks/ceph-ansible/site.yml",
    ]
  }
  # provisioner "remote-exec" {
  #   inline = [
  #     "ansible-playbook -i inventory.ini playbook/kube-ceph/kube-ceph-destroy.yml -e project=${var.project} -e dnszone=${var.dnszone} -f 50 -T 30",
      
  # }
  provisioner "local-exec" {
    command = "ssh-keygen -R ${var.project}-kube-ctlr.${var.dnszone}"
  }
  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no linux@${var.project}-kube-ctlr.${var.dnszone}:mon_ips ."
  }
}

resource "null_resource" "provision-kube-ceph" {
  depends_on = ["null_resource.provision-mgt","openstack_dns_recordset_v2.ceph-mons"]
  connection {
#      host     = "${openstack_networking_floatingip_v2.ceph-mgt.address}"
      host     = "${var.project}-kube-ctlr.${var.dnszone}"
      user     = "${var.ssh_user_name}"
      agent = true
  }
  provisioner "file" {
    source = "playbooks/kube-ceph"
    destination = "playbooks"
  }
  provisioner "remote-exec" {
    inline = [
      "ansible-playbook -i inventory.ini playbooks/kube-ceph/kube-ceph.yml -e project=${var.project} -e dnszone=${var.dnszone} -f 50 -T 30", 
    ]
  }
  # provisioner "remote-exec" {
  #   inline = [
  #     "ansible-playbook -i inventory.ini playbook/kube-ceph/kube-ceph-destroy.yml -e project=${var.project} -e dnszone=${var.dnszone} -f 50 -T 30",
      
  # }
}

resource "openstack_blockstorage_volume_v2" "ceph-osd-image-vols" {
  count           = "${var.ceph-osd_count}"
  name = "${var.project}-${format("vol-%03d", count.index + 1)}"
  size = "${var.image_vol_size}"
  volume_type = "${var.image_vol_type}"
  availability_zone = "${var.availability_zone}"
  image_id = "${var.image_uuid}"
}

resource "openstack_compute_instance_v2" "ceph-osds" {
#  depends_on = ["openstack_networking_router_interface_v2.interface"]
  count           = "${var.ceph-osd_count}"
  name            = "${var.project}-ceph-osd-${format("%02d", count.index+1)}"
  image_name      = "${var.image_name}"				#"bitnami-ceph-osdstack-7.0.22-1-linux-centos-7-x86_64-mp"
  flavor_name     = "${var.flavor_name}"
  key_pair        = "${openstack_compute_keypair_v2.otc.name}"
  availability_zone = "${var.availability_zone}"
  security_groups = [
    "${openstack_compute_secgroup_v2.secgrp_ceph.name}"
  ]
  network {
    port = "${element(openstack_networking_port_v2.osds-port.*.id, count.index)}"
#    uuid = "${data.openstack_networking_network_v2.network.id}"
    access_network = true
  }
  block_device {
    uuid                  = "${element(openstack_blockstorage_volume_v2.ceph-osd-image-vols.*.id, count.index)}"
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
  lifecycle {
    prevent_destroy = false
    create_before_destroy = false
  }
}

resource "openstack_networking_port_v2" "osds-port" {
  count              = "${var.ceph-osd_count}"
  network_id         = "${data.openstack_networking_network_v2.network.id}"
  security_group_ids = [
    "${openstack_compute_secgroup_v2.secgrp_ceph.id}",
  ]
  admin_state_up     = "true"
  fixed_ip           = {
    subnet_id        = "${data.openstack_networking_subnet_v2.subnet.id}"
  }
}

resource "openstack_compute_keypair_v2" "otc" {
  name       = "${var.project}-otc-ceph"
  public_key = "${file("${var.public_key_file}")}"
}

provider "openstack" {
  user_name   = "${var.otc_username}"
  password    = "${var.otc_password}"
  tenant_name = "${var.otc_tenant_name}"
  domain_name = "${var.otc_domain_name}"
  auth_url    = "${var.endpoint}"
}

resource "openstack_compute_secgroup_v2" "secgrp_ceph" {
  name        = "${var.project}-secgrp-ceph-osd"
  description = "CEPH-OSD stack Security Group"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 80
    to_port     = 80
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 443
    to_port     = 443
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 7000
    to_port     = 7000
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    self        = true
  }
  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "udp"
    self        = true
  }
  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    cidr        = "${data.openstack_networking_subnet_v2.subnet.cidr}"
  }
}

resource "openstack_blockstorage_volume_v2" "vols" {
  count           = "${var.ceph-osd_count * var.disks-per-osd_count}"
  name = "${var.project}-${format("vol-%03d", count.index + 1)}"
  size = "${var.vol_size}"
  volume_type = "${var.vol_type}"
  availability_zone = "${var.availability_zone}"
}

resource "openstack_compute_volume_attach_v2" "vas" {
  count           = "${var.ceph-osd_count * var.disks-per-osd_count}"
  instance_id = "${element(openstack_compute_instance_v2.ceph-osds.*.id, count.index / var.disks-per-osd_count)}"
  volume_id   = "${element(openstack_blockstorage_volume_v2.vols.*.id, count.index)}"
}
