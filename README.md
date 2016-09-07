# What is Kubernetes?
Kubernetes is an open-source platform for automating deployment, scaling, and operations of application containers across clusters of hosts, providing container-centric infrastructure.

With Kubernetes, you are able to quickly and efficiently respond to customer demand:

 - Deploy your applications quickly and predictably.
 - Scale your applications on the fly.
 - Seamlessly roll out new features.
 - Optimize use of your hardware by using only the resources you need.

### Kubernetes is
 - portable: public, private, hybrid, multi-cloud
 - extensible: modular, pluggable, hookable, composable
 - self-healing: auto-placement, auto-restart, auto-replication, auto-scaling

# Indigo Kubernetes Cluster

To running the container services there is a Kubernetes Cluster installed for Indigo services. Currently the following services using Container technology:
 - accounting
 - zabbix monitoring
 - im

# Kubernetes Cluster Installation

## Components
The initial cluster is planned with 2 masters and 3 minions/nodes. Each master will also have an ETCD datastore component installed in addition to the Kubernetes master component.
 - 3 etcd 
 - 2 masters
 - 3 minions
 - VIP

The scripts, and playbooks are written to installing the Kubernetes Cluster for the Indigo Project with all the installed add-ons on Base Operation System: Fedora 23.
It's written to install a Kubernetes Cluster with 2 Master Server, and with N piece of LoadBalancer and Node Servers.

## Ansible

The playbook provided for Kubernetes https://github.com/kubernetes/contrib/ does not support the HA installation by default. The document explains in detail, how the HA installation was performed and the changes required in the playbook for the same.

## Installation

The service is able to run on Fedora 23 and on Ubuntu 11 servers.

### Pre-requisites
The playbooks are run as user root. The ssh key needs to be copied on all nodes. The following packages should be installed before playbook run on all machine.

- python 
- git 
- python-netaddr
- python-dnf 
- libselinux-python

To make haproxy working we need to change net.ipv4.ip_nonlocal_bind kernelparameter as well, so we need to edit /etc/sysctl.conf
```
net.ipv4.ip_nonlocal_bind=1
sysctl -p
```
### Playbook configuration changes for HA setup
 1. Replace master ip (taken originally as first host in the inventory listed under group master) with vip.. (to do .. use a variable vip istead of hardcoding)
```
./roles/kubernetes-addons/templates/kube-addons.service.j2:9:Environment="KUBERNETES_MASTER_NAME="<VIP>" 
./roles/kubernetes-addons/templates/kube-addons.upstart.j2:10:env KUBERNETES_MASTER_NAME=<VIP>
./roles/kubernetes/defaults/main.yml:41:kube_cert_ip: "<VIP>,IP:<MASTER1>,IP:<MASTER2>" 
./roles/kubernetes/files/make-ca-cert.sh:95:master_name="<VIP>" 
./roles/kubernetes/tasks/gen_tokens.yml:15:    - "<VIP>" 
./roles/kubernetes/templates/config.j2:24:KUBE_MASTER="--master=https://<VIP>:8443" 
./roles/master/tasks/main.yml:34:    src: "{{ kube_token_dir }}/{{ item }}-<VIP>.token" 
./roles/master/templates/controller-manager.kubeconfig.j2:8:    server: https://<VIP>:8443}}
./roles/master/templates/kubectl.kubeconfig.j2:8:    server: https://<VIP>:8443
./roles/master/templates/scheduler.kubeconfig.j2:8:    server: https://<VIP>:8443
./roles/node/templates/kubelet.j2:14:KUBELET_API_SERVER="--api-servers=https://<VIP>:8443" 
./roles/node/templates/kubelet.kubeconfig.j2:8:    server: https://<VIP>:8443 }}
./roles/node/templates/proxy.kubeconfig.j2:13:    server: https://<VIP>:8443 }}
./roles/opencontrail-provision/tasks/nodes.yml:3:  command: docker run opencontrail/config:2.20 /usr/share/contrail-utils/provision_vrouter.py --api_server_ip <VIP> --host_name "{{ inventory_hostname }}{% if hostvars[inventory_hostname]['ansible_domain'] != "" %}.{{ hostvars[inventory_hostname]['ansible_domain'] }}{% endif %}" --host_ip "{{ hostvars[inventory_hostname]['ipaddr'] }}" 
```
 2. Change install_addons to true in group_vars/all.yml, change user to root
 3. Add last arugment to `./roles/master/templates/apiserver.j2`
```
KUBE_API_ARGS="{{ apiserver_extra_args | default('') }} --tls-cert-file={{ kube_cert_dir }}/server.crt --tls-private-key-file={{ kube_cert_dir }}/server.key --client-ca-file={{ kube_cert_dir }}/ca.crt --token-auth-file={{ kube_token_dir }}/known_tokens.csv --service-account-key-file={{ kube_cert_dir }}/server.crt --bind-address={{ kube_apiserver_bind_address }} --apiserver-count=2" 
```
 4. Add the `--leader-elect=true` to `./roles/master/templates/scheduler.j2` and `./roles/master/templates/controller-manager.j2 controller-manager.j2`

### Installing the LB components
We will first start with installing ha-proxy and keepalived on the 3 VMs. We have written a basic playbook for this purpose with 2 roles :- haproxy and keepalived
The inventory file looks as below:
```
[lb]
IP1
IP2
IP3
```

The playbook is run using the following command:
```
ansible-playbook -i inventory site.yml
```

### Installing the Kubernetes cluster
The original playbook was changed so that we are able to install HA kubernetes cluster. The updated playbook will be uploaded to the Indigo git repo.
We will first install the cluster with the following inventory, which will install 1 master, an etcd cluster of nodes and 3 

The inventory files looks as below:
```
[masters]
<MASTER1>

[etcd]
<ETCD1>
<ETCD2>
<ETCD3>

[nodes]
<NODE1>
<NODE2>
<NODE3>
```

The playbook is run using the following command:
```
INVENTORY=inventory.ha ./setup.sh 
```
After the cluster is installed, we will run the playbook again to add another master to the cluster. 

Before the playbook is run, make sure to copy the `/etc/kubernetes` directory from the first master to the 2nd master. This will make sure that both the masters will use the same tokens for authentication. Make sure not to copy the certs directory so that the certificates for master2 can be generated locally on that machine.
The master IP in the above inventory file is now changed to <MASTER2> and the playbook is rerun with the following command:
```
INVENTORY=inventory.ha ./setup.sh --tags=masters
```

## Addon-list and installation sequence:
1. HaProxy LoadBalancer for Master-Node communication
2. Kubernetes Cluster installation (with etcd, masters and nodes)
3. Add-on Service installation
  * Elasticsearch logging service
  * SkyDNS DNS Service
  * Kube-dash and Kubernetes-UI Dashboards
  * Heapster monitoring with InfluxDB and Grafana UI
  * Cinder Volume Management on OpenStack
  * LoadBalancer uService for service routing  

## Automation
The full installation automized with a simple shell script for Fedora 23.

* Pull the repositoy to your installer Machine
* Adjust the setup.conf with the necessary parameters. Example: LB_IP=1.2.3.4 You can extend the list of the servers as much as you need. If you don't have/need any kind of informations, which is listed in file just delete the line.
* Run setup.sh command

## Backup/Restore
### Loadbalancer/Kubernetes
There is no backup service for the Main components, as it can be restored any time from the Playbooks.

### ETCD Cluster
Etcd is a distributed, consistent key-value store for shared configuration and service discovery. Because of this purpose it's very important to keep it's datas. However etcd have a very small amount of data (~2-3MB), so it make no sence to setup a big backup service for this purpose.

A simple bash script written to create daily backups, and storing on the servers. 

#### Restore
The restore of the etcd database running with the following command:
```
etcd \
      -data-dir=%backup_data_dir% \
      -force-new-cluster \
      ...
```
Once the cluster started properly you can stop this service, and restart again without the force-ne-cluster parameter
#### Known and open issues

