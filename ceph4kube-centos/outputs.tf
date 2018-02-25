# output "ceph-mgt public address" {
#   value = "${openstack_networking_floatingip_v2.ceph-mgt.address}"
# }

output "ceph-mon address" {
  value = "${openstack_compute_instance_v2.ceph-mons.*.access_ip_v4}"
}

output "Final message" {
  value = "Congratulations! Your Ceph cluster have been successfully setup and configured in your k8s cluster.\nGood luck!"
}

# output "ceph-osd address" {
#   value = "${openstack_compute_instance_v2.ceph-osds.*.access_ip_v4}"
# }

# output "ceph-osd names" {
#   value = "${openstack_compute_instance_v2.ceph-osds.*.name}"
# }


