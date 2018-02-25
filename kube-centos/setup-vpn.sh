#!/bin/bash
# if an old openvpn-kube client process is still running kill it before running the playbook
# vpn_floatingip=$1,
project=$5
ps -ef | grep ${project}-vpn | sudo kill `awk '{print $2}'`
ssh-keygen -R $1
ssh -o StrictHostKeyChecking=no $1 hostname
printf "[vpn]\n$1" > inventory
ansible-playbook -i inventory playbooks/openvpn/site.yml -e kube_ctlr_ip=$2 -e kube_service_addresses=$3 -e server_network=$4 -e project=$5 -e kube_pods_subnet=$6
