resource "openstack_networking_floatingip_v2" "vpn" {
  depends_on = ["openstack_compute_instance_v2.vpn"]
  port_id  = "${openstack_networking_port_v2.vpn-port.id}"
  pool  = "${var.external_network}"
}

resource "openstack_networking_floatingip_v2" "kube-ctlr" {
  depends_on = ["openstack_compute_instance_v2.kube-ctlr"]
  port_id  = "${element(openstack_networking_port_v2.ctlr-port.*.id, count.index)}"
  count = "${var.kube-ctlr_count}"
  pool  = "${var.external_network}"
}

resource "openstack_compute_instance_v2" "vpn" {
  depends_on = ["openstack_networking_router_interface_v2.interface"]
  name            = "${var.project}-vpn"
  image_name      = "${var.vpn_image_name}"	
  flavor_name     = "${var.vpn_flavor_name}"
  key_pair        = "${openstack_compute_keypair_v2.otc.name}"
  availability_zone = "${var.availability_zone}"
  network {
    port = "${openstack_networking_port_v2.vpn-port.id}"
    uuid = "${openstack_networking_network_v2.network.id}"
    access_network = true
  }
}

resource "openstack_networking_port_v2" "vpn-port" {
  network_id         = "${openstack_networking_network_v2.network.id}"
  security_group_ids = [
    "${openstack_compute_secgroup_v2.secgrp_vpn.id}",
    "${openstack_compute_secgroup_v2.secgrp_kube.id}",
    "${openstack_compute_secgroup_v2.secgrp_jmp.id}",
  ]
  admin_state_up     = "true"
  fixed_ip           = {
    subnet_id        = "${openstack_networking_subnet_v2.subnet.id}"
  }
  allowed_address_pairs = {
    ip_address = "1.1.1.1/0"
  }
}

resource "openstack_blockstorage_volume_v2" "kube-ctlr-image-vols" {
  count           = "${var.kube-ctlr_count}"
  name = "${var.project}-${format("vol-%03d", count.index + 1)}"
  size = "${var.image_vol_size}"
  volume_type = "${var.image_vol_type}"
  availability_zone = "${var.availability_zone}"
  image_id = "${var.image_uuid}"
}

resource "openstack_compute_instance_v2" "kube-ctlr" {
  depends_on = ["openstack_networking_router_interface_v2.interface"]
  count           = "${var.kube-ctlr_count}"
  name            = "${var.project}-kube-ctlr-${format("%02d", count.index+1)}"
  flavor_name     = "${var.ctlr_flavor_name}"
  key_pair        = "${openstack_compute_keypair_v2.otc.name}"
  availability_zone = "${var.availability_zone}"
  network {
    port = "${element(openstack_networking_port_v2.ctlr-port.*.id, count.index)}"
    uuid = "${openstack_networking_network_v2.network.id}"
    access_network = true
  }
  block_device {
    uuid                  = "${element(openstack_blockstorage_volume_v2.kube-ctlr-image-vols.*.id, count.index)}"
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
}

resource "openstack_networking_port_v2" "ctlr-port" {
  count              = "${var.kube-ctlr_count}"
  network_id         = "${openstack_networking_network_v2.network.id}"
  security_group_ids = [
    "${openstack_compute_secgroup_v2.secgrp_jmp.id}",
    "${openstack_compute_secgroup_v2.secgrp_kube.id}",
  ]
  admin_state_up     = "true"
  fixed_ip           = {
    subnet_id        = "${openstack_networking_subnet_v2.subnet.id}"
  }
  allowed_address_pairs = {
    ip_address = "1.1.1.1/0"
  }
}

resource "null_resource" "provision-work" {
  count = "${var.kube-work_count}"
  connection {
    bastion_host = "${openstack_networking_floatingip_v2.vpn.address}"
    bastion_user = "${var.vpn_user_name}"
    host     = "${element(openstack_compute_instance_v2.kube-work.*.access_ip_v4, count.index)}"
    user     = "${var.ssh_user_name}"
    agent = true
    timeout = 600
  }
  provisioner "remote-exec" {
    inline = [
      "sudo systemctl disable firewalld",
      "sudo systemctl stop firewalld",
    ]
  }
}

resource "null_resource" "provision-vpn" {
  depends_on = ["openstack_networking_floatingip_v2.vpn", "null_resource.provision-local-setup"]
  connection {
    host     = "${openstack_networking_floatingip_v2.vpn.address}"
    user     = "${var.vpn_user_name}"
    agent = true
  }
  provisioner "file" {
    source = "etc/sources.list"
    destination = "sources.list"
  }
  provisioner "file" {
    source = "etc/ssh_config"
    destination = "ssh_config"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo cp sources.list ${var.sources_list_dest}", 
      "sudo apt-get -y update",
      "sudo apt-get -y install python",
      "sudo cp ssh_config /etc/ssh/ssh_config",
    ]
  }
  provisioner "local-exec" {
    command = "./setup-vpn.sh ${openstack_networking_floatingip_v2.vpn.address} ${openstack_compute_instance_v2.kube-ctlr.0.access_ip_v4} ${var.kube_service_addresses} ${var.vpn_network} ${var.project} ${var.kube_pods_subnet}"
  }
  provisioner "local-exec" {
    command = "echo -n ${join(" ", openstack_compute_instance_v2.kube-work.*.access_ip_v4)} ${join(" ", openstack_compute_instance_v2.kube-ctlr.*.access_ip_v4)} > instance-ips.out"
  }
  provisioner "local-exec" {
    command = "./check-ips.sh ${var.ssh_user_name}"
  }
}


resource "null_resource" "provision-kubespray" {
  depends_on = ["openstack_compute_instance_v2.kube-work", "openstack_compute_instance_v2.kube-ctlr", "null_resource.provision-ctlr", "null_resource.provision-work", ]
  connection {
      host     = "${openstack_networking_floatingip_v2.kube-ctlr.0.address}"
      user     = "${var.ssh_user_name}"
      agent = true
  }
  provisioner "file" {
    source = "playbooks.tgz"
    destination = "playbooks.tgz"
  }  
  provisioner "file" {
    content = "${join("\n", formatlist("%s ansible_host=%s", openstack_compute_instance_v2.kube-ctlr.*.name, openstack_compute_instance_v2.kube-ctlr.*.access_ip_v4))}\n${join("\n", formatlist("%s ansible_host=%s", openstack_compute_instance_v2.kube-work.*.name, openstack_compute_instance_v2.kube-work.*.access_ip_v4))}\n\n[kube-master]\n${join("\n", openstack_compute_instance_v2.kube-ctlr.*.name)}\n\n[etcd]\n${join("\n", openstack_compute_instance_v2.kube-ctlr.*.name)}\n\n[kube-node]\n${join("\n", openstack_compute_instance_v2.kube-work.*.name)}\n\n[k8s-cluster:children]\nkube-node\nkube-master\n"
    destination = "inventory.ini"
  }
  provisioner "remote-exec" {
    inline = [
      "tar zxvf playbooks.tgz",
      "sudo yum -y install ansible",
      "sudo yum -y install python-pip",
      "sudo pip install --upgrade jinja2",
      "sudo systemctl disable firewalld",
      "sudo systemctl stop firewalld",
      "cd playbooks; git clone https://github.com/kubernetes-incubator/kubespray.git; cd ..",
      "ansible-playbook -b -i inventory.ini playbooks/kubespray/cluster.yml -e dashboard_enabled=true -e '{kubeconfig_localhost: true}' -e kube_network_plugin=flannel -e cluster_name=kube.${var.dnszone} -e domain_name=kube.${var.dnszone} -e kube_service_addresses=${var.kube_service_addresses} -e kube_pods_subnet=${var.kube_pods_subnet} -f 50 -T 30"
    ]
  }
}

resource "null_resource" "provision-helm" {
  depends_on = ["null_resource.provision-kubespray"]
  connection {
      host     = "${openstack_networking_floatingip_v2.kube-ctlr.0.address}"
      user     = "${var.ssh_user_name}"
      agent = true
  }
  provisioner "remote-exec" {
    inline = [
      "wget https://storage.googleapis.com/kubernetes-helm/helm-v2.8.1-linux-amd64.tar.gz",
      "tar zxf helm-v2.8.1-linux-amd64.tar.gz",
      "sudo mv linux-amd64/helm /usr/local/bin",
      "kubectl create clusterrolebinding helm-admin --clusterrole=cluster-admin --user=system:serviceaccount:kube-system:default", # TODO: check if kubespray binds roles
      "helm init",
      "until helm ls; do echo Waiting for tiller...; sleep 1; done",
#      "sleep 5",
    ]
  }
}

data "template_file" "collectd" {
  template = "${file("etc/collectd.conf.tpl")}"
  vars {
    graphite_host = "go-carbon.mon.svc.kube.${var.dnszone}"
    # graphite_host = "${openstack_compute_instance_v2.grafana.access_ip_v4}"
  }
}

resource "null_resource" "provision-collectd" {
#  count = "${var.client_count}"
  depends_on = [ "null_resource.provision-landscape", ]
  triggers {
#    mount = "${element(null_resource.provision-clients-mount.*.id, count.index)}"
    graphite = "go-carbon.mon.svc.kube.${var.dnszone}"
  }
  connection {
    host     = "${openstack_networking_floatingip_v2.kube-ctlr.0.address}"
    user     = "${var.ssh_user_name}"
    agent = true
    timeout = 600
  }
  provisioner "file" {
    content = "${data.template_file.collectd.rendered}"
    destination = "collectd.conf"
  }
  provisioner "remote-exec" {
    inline = [
      "ansible-playbook -i inventory.ini playbooks/miscafter/collectd.yml",
    ]
  }
}

resource "null_resource" "provision-resolv-nfs" {
  depends_on = ["null_resource.provision-kubespray", "null_resource.provision-helm"]
  connection {
      host     = "${openstack_networking_floatingip_v2.kube-ctlr.0.address}"
      user     = "${var.ssh_user_name}"
      agent = true
  }
  provisioner "file" {
    source = "playbooks/miscafter"
    destination = "/home/linux/playbooks"
  }  
  provisioner "remote-exec" {
    inline = [
      "ansible-playbook -i inventory.ini playbooks/miscafter/miscafter.yml -e dnszone=${var.dnszone} -e project=${var.project}",      
    ]
  }
}

resource "null_resource" "provision-landscape" {
  depends_on = ["null_resource.provision-resolv-nfs", "null_resource.provision-kubespray", "null_resource.provision-helm"]
  connection {
      host     = "${openstack_networking_floatingip_v2.kube-ctlr.0.address}"
      user     = "${var.ssh_user_name}"
      agent = true
  }
  provisioner "local-exec" {
      command = "./tar-charts.sh"
  }  
  provisioner "file" {
    source = "../chart-deplo.tgz"
    destination = "/home/linux/chart-deplo.tgz"
  }
  provisioner "file" {
    source = "approve.sh"
    destination = "approve.sh"
  }  
  provisioner "remote-exec" {
    inline = [
      # "git clone https://github.com/onedata/k8s-deployment.git", # Uncomment when images will be downloadable
      # "helm repo add onedata https://onedata.github.io/charts/",
      "tar zxvf chart-deplo.tgz",
      "kubectl label node ${var.project}-kube-work-01 onedata-service=provider",
      # "kubectl taint node ${var.project}-kube-work-01 onedata-service=provider:NoSchedule",
      "kubectl create clusterrolebinding default-admin --clusterrole=cluster-admin --user=system:serviceaccount:default:default",
      "chmod +x approve.sh",
      "nohup ./approve.sh > approve.log 2>&1 &",
      "sleep 1",
      "sed -i 's/{{dnszone}}/${var.dnszone}/' wr-test-job.yaml",
    ]
  }
}

resource "null_resource" "provision-local-setup" {
  depends_on = ["openstack_networking_floatingip_v2.kube-ctlr","null_resource.provision-work"]
  provisioner "local-exec" {
    command = "./local-setup.sh ${var.project} ${var.kube-ctlr_count} ${var.kube-work_count} 0 0"
  }
}

resource "null_resource" "provision-ctlr" {
  depends_on = [
    "openstack_networking_floatingip_v2.kube-ctlr",
    "null_resource.provision-work",
    "null_resource.provision-local-setup",
  ]
  count = "${var.kube-ctlr_count}"
  connection {
      host     = "${element(openstack_networking_floatingip_v2.kube-ctlr.*.address, count.index)}"
      user     = "${var.ssh_user_name}"
      agent = true
  }
  provisioner "file" {
    source = "etc.tgz"
    destination = "etc.tgz"
  }
  provisioner "remote-exec" {
    inline = [
      "tar zxvf etc.tgz",
      "sudo cp etc/ssh_config /etc/ssh/ssh_config",
      "sudo systemctl disable firewalld",
      "sudo systemctl stop firewalld",
    ]
  }
}

resource "openstack_blockstorage_volume_v2" "kube-work-image-vols" {
  count           = "${var.kube-work_count}"
  name = "${var.project}-${format("vol-%03d", count.index + 1)}"
  size = "${var.image_vol_size}"
  volume_type = "${var.image_vol_type}"
  availability_zone = "${var.availability_zone}"
  image_id = "${var.image_uuid}"
}

resource "openstack_compute_instance_v2" "kube-work" {
  depends_on = ["openstack_networking_router_interface_v2.interface"]
  count           = "${var.kube-work_count}"
  name            = "${var.project}-kube-work-${format("%02d", count.index+1)}"
  flavor_name     = "${var.work_flavor_name}"
  key_pair        = "${openstack_compute_keypair_v2.otc.name}"
  availability_zone = "${var.availability_zone}"

  network {
    port = "${element(openstack_networking_port_v2.work-port.*.id, count.index)}"
    uuid = "${openstack_networking_network_v2.network.id}"
    access_network = true
  }
  block_device {
    uuid                  = "${element(openstack_blockstorage_volume_v2.kube-work-image-vols.*.id, count.index)}"
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }
  lifecycle {
    prevent_destroy = false
  }
}

resource "openstack_networking_port_v2" "work-port" {
  count              = "${var.kube-work_count}"
  network_id         = "${openstack_networking_network_v2.network.id}"
  name = "${var.project}-work-${format("%02d", count.index+1)}"
  security_group_ids = [
    "${openstack_compute_secgroup_v2.secgrp_kube.id}",
  ]
  admin_state_up     = "true"
  fixed_ip           = {
    subnet_id        = "${openstack_networking_subnet_v2.subnet.id}"
  }
  allowed_address_pairs = {
    ip_address = "1.1.1.1/0"
  }
}

resource "openstack_compute_keypair_v2" "otc" {
  name       = "${var.project}-otc"
  public_key = "${file("${var.public_key_file}")}"
}

resource "openstack_networking_network_v2" "network" {
  name           = "${var.project}-network"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "subnet" {
  name            = "${var.project}-subnet"
  network_id      = "${openstack_networking_network_v2.network.id}"
  cidr            = "${var.vpc_subnet}"
  ip_version      = 4
  dns_nameservers = ["8.8.8.8", "100.125.4.25"]
}

provider "openstack" {
  user_name   = "${var.otc_username}"
  password    = "${var.otc_password}"
  tenant_name = "${var.otc_tenant_name}"
  domain_name = "${var.otc_domain_name}"
  auth_url    = "${var.endpoint}"
}
resource "openstack_networking_router_route_v2" "vpn_route" {
  depends_on       = ["openstack_networking_router_interface_v2.interface"]
  router_id        = "${openstack_networking_router_v2.router.id}"
  destination_cidr = "${var.vpn_network}/24"
  next_hop         = "${openstack_compute_instance_v2.vpn.access_ip_v4}"
}

resource "openstack_networking_router_v2" "router" {
  name             = "${var.project}-router"
  admin_state_up   = "true"
  external_gateway = "0a2228f2-7f8a-45f1-8e09-9039e1d09975"
  enable_snat = true
}

resource "openstack_networking_router_interface_v2" "interface" {
  router_id = "${openstack_networking_router_v2.router.id}"
  subnet_id = "${openstack_networking_subnet_v2.subnet.id}"
}

resource "openstack_compute_secgroup_v2" "secgrp_jmp" {
  name        = "${var.project}-secgrp-jmp"
  description = "Jumpserver Security Group"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 6443
    to_port     = 6443
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 8443
    to_port     = 8443
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
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    cidr        = "0.0.0.0/0"
  }
}

resource "openstack_compute_secgroup_v2" "secgrp_kube" {
  name        = "${var.project}-secgrp-kube"
  description = "Kube Security Group"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 53
    to_port     = 53
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 53
    to_port     = 53
    ip_protocol = "udp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 80
    to_port     = 80
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 3000
    to_port     = 3000
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 8082
    to_port     = 8082
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
    from_port   = 5555
    to_port     = 5555
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 5556
    to_port     = 5556
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 6665
    to_port     = 6665
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 6666
    to_port     = 6666
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 7443
    to_port     = 7443
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 8443
    to_port     = 8443
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 8876
    to_port     = 8876
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 8877
    to_port     = 8877
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 9443
    to_port     = 9443
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
}

resource "openstack_compute_secgroup_v2" "secgrp_vpn" {
  name        = "${var.project}-secgrp-vpn"
  description = "VPN stack Security Group"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 1194
    to_port     = 1194
    ip_protocol = "udp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port   = 1194
    to_port     = 1194
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
}

