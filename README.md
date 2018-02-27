# Terraform/ansible/helm files for preparing testing environment for Onedata on OTC

## Repo structure
* kube-centos - terraform and ansible files for creating infrastructure and deploying kubernetes cluster and VPN server. 
* ceph4kube-centos - terraform and ansible files for creating infrastructure and deploying ceph cluster in the same VPC as the kubernetes cluster
* charts - consists of helm charts for deploying onedata
* scale-3p-land.yaml - helm landscape for deploying onedata

## Onedata testbed
The testbed, which can be build by the scripts of this repo, alows for creating the infrastructure on OTC, installing and configuring of the necessary software components, deploying onedata services and running test jobs.

### Onedata components
The onedata components, which will get deployed is shown in figure below. 

![onedata components](https://github.com/onedata/onedata-otc-benchmark/blob/master/onedatacomp-01.png)

Three providers can be used for testing. In the current version two providers (OTC-Cache and OTC-Prov1) have storage attached automatically. More storage options, e.g., S3, POSIX or NFS, can be manually configured and added via the web browser user interface. The Ceph object based storage is attched to OTC-Cache and an OTC SFS (Scalable File Service) share is provided to OTC-Prov1. There is one space defined (OTC-Space), which is supported by those two providers. The prepared oneclient jobs write and after that read files to and from OTC-Space. The clients connect to OTC-Cache and access data directly on the Ceph storage. 

### Infrastructure and services

The above onedata components are deployed using the following infrastructure, which is created by terraform scripts.

![infrastructure and services](https://github.com/onedata/onedata-otc-benchmark/blob/master/onedatacomp-02.png)

All VMs exept the VPN server are second generation machines (flavor h2.3xlarge.10). The VPN server is a h1 machine with 2CPUs.

### Deployment process

The deployment process consists of few main steps shown in the diagram below.

![deployment process](https://github.com/onedata/onedata-otc-benchmark/blob/master/OTC-bench-deploy.png)

Those steps are described in mmore details below.

## Configuring k8s cluster

In order to build your cluster you need to:
* run ssh-agent and add your key. It will further be used to login into the created VMs.
* provide your openstack credentials by editting parameter.tvars. The username should be the same as shown in the OTC console. You can not use the email or mobile number, which can also be used to login to the OTC web console. 
* eventually change values in varaibles.tf according to the comments in this file.

The testing environment uses public DNS. It is required to have a public domain under control. In order to integrate kube-dns with your public domain you need to:
  * have a registered Internet domain which uses (delegates to) the following nameservers:
    * ns1.open-telekom-cloud.com.
    * ns2.open-telekom-cloud.com.
For example, if using dot.tk free domain service click on Service->My domains->Manage Domain->Management Tools->Nameservers, check Use custom nameservers and enter the open-telekom-cloud nameservers. 

Edit kube-centos/variables.tf and set at least the following vars:
* dnszone - your registered Internet domain. The publicly resolvable cluster domain will be kube.{{dnszone}}.
* project - project name. It is used to prefix VM names. It should be unique among OTC as it is used to create names of VMs.
* public_key_file - the path to your ssh public key.
You can also set the variables specifying the networks to be used (in case of conficts with the existing ones):
* kube_service_addresses
* kube_pods_subnet
* vpn_network
* vpc_subnet


The variables can also be provided interactively or set as command line args. For example:
```
terraform apply -var project=example_project -var email=joe@example.com ....
```

## Configuring the Ceph cluster

Edit ceph4kube-centos/variables.tf and set the variables for the Ceph cluster. Note that the values of related variables (project, dnszone) should be the same as for the k8s cluster. 

## Running
Build your k8s cluster issuing:
```
cd kube-centos
terraform init
terraform apply -var-file ../parameter.tvars
```

After a successful build go to the ceph4kube-centos directory and run terraform using the same arguments:

```
cd ../ceph4kube-centos
terraform init
terraform apply -var-file ../parameter.tvars
```

## Accessing your k8s cluster
After a successful build the public and private IPs of the k8s cluster master node are displayed. In order to have access to the private addresses you need to connect to the VPN server, which has been prepared. If the terraform has been run from a linux machine then on that machine a VPN client has been run already by the scripts. You can also use the "scp ubuntu@..." commands displayed after successful terraform execution to manually start a VPN connection and kube proxy on another machine, e.g., your laptop or desktop. An example commands looks like:
```
scp ubuntu@80.158.20.236:laptop.sh .; ./laptop.sh
```
The kubernetes master node has public address and can be access via ssh on linux@{{project}}-kube-ctlr.{{dnszone}}. For example:
```
ssh linux@myproject-kube-ctlr.my.domain
```

## Configuring the landscape

Create a SFS (Scalable File Service) share on OTC for the VPC which has been created by terraform. It is called {{project}}-router. Replace {{project}} with the value of project variable you specified earlier. Note the SFS share id and place it in charts/volume-sfs/values.yaml. Eventually modify the size, which defaults to 3T. Do not create volumes with less than 3000GB sizes.

## Grafana

Grafana URL is http://grafana.mon.svc.kube.{{dnszone}}:80/. An active VPN connection is needed to view it. A basic dashboard "oc-trans-rate" has been uploaded. It shows oneclients aggregated read and write rates for ceph. 

## Deploying onedata

Login to the kubernetes master node:
```
ssh {{project}}-kube-ctlr.{{dnszone}} -l linux
```
Run the following command to deploy onedata:
```
helm install -f scale-3p-land.yaml charts/cross-support-job-3p -n st
```
Observe the progress of the deployment and wait until all pods reach the Running status:
```
watch kubectl get pod
```
Use a browser to login to onezone and check the deployment was successful. The URL is https://st-onezone.default.svc.kube.{{dnszone}}/ and credentials are admin:password.

## Preparing and running a simple job

A kubernetes job definition file "wr-test-job.yaml" has been uploaded to the master node. The job writes with dd a file, then read it 10 time and remove it. In order to configure the job an access token from onezone should be placed in the job file. Set the number of parallel jobs with the "parallelism" parameter. The file size can be set by modifying the "count=" part of the command. The default file size is 10GB and the number of jobs is 20. Run the job with:
```
kubectl create -f wr-test-job.yaml
```

## Destruction
Destroy the infrastructure with "terraform destroy" command. Use the same parameters as for the "terraform apply" command. Destroy in reverse order: the ceph cluster first:
```
cd ceph4kube-centos
terraform destroy -var-file ../parameter.tvars
cd ../kube-centos
terraform destroy -var-file ../parameter.tvars
```

## Example command flow 

### Prepare ssh 
```
eval `ssh-agent`
ssh-key
```
### Download the scripts
```
git clone https://github.com/darnik22/onedata-otc-tests.git
```
### Configure k8s cluster
```
cd onedata-otc-tests
vi parameter.tvars
cd kube-centos
vi variables.tf
```
### Create the k8s cluster
```
terraform init
terraform apply -var-file ../parameter.tvars -var project=myproject -var dnszone=my.domain
```
Upon success the IP of the master node and VPN server are dysplayed in green color.
### Configure Ceph
```
cd ../ceph4kube-centos
vi variables.tf
```
### Create the Ceph cluster
```
terraform init
terraform apply -var-file ../parameter.tvars -var project=myproject -var dnszone=my.domain
```
Upon success the IP of the Ceph monitor nodes are dysplayed in green color.

### Create SFS share using OTC Web console
### Login to the master node
```
ssh -A linux@myproject-kube-ctlr.my.domain
```
### Configure SFS volume for onedata
```
cd ..
vi charts/volume-sfs/values.yaml
```
### Deploy onedata
```
helm install -f scale-3p-land.yaml charts/cross-support-job-3p -n st
watch kubectl get pod
```
When this task succeseds the status of pods should be running and the number of restarts should be zero. Note that it could take few minutes to reach this state.

### Configure the test job
Copy access token from onezone (https://st-onezone.default.svc.kube.my.domain) and replace it with the one in the file wr-test-job.yaml.
```
vi wr-test-job.yaml
kubectl create -f wr-test-job.yaml
```
### Observe grafana (http://grafana.mon.svc.kube.my.domain)
...

### Destroy the infrastructure
```
cd ceph4kube-centos
terraform destroy -var-file ../parameter.tvars
cd ../kube-centos
terraform destroy -var-file ../parameter.tvars

```

## Known issues
The environment is based on IP over IB for transferring data between k8s and ceph. Sometimes the interface ib0 on some VMs does not get up, which causes the scripts to fail. This is a problem with OTC itself. If this happens the VMs with failed ib0 can be restarted, which usually helps. When ib0 gets up the "terraform apply" command can be issued again.