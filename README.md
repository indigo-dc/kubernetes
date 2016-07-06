# Kubernetes Cluster Installation

## Components
The initial cluster is planned with 2 masters and 3 minions/nodes. Each master will also have an ETCD datastore component installed in addition to the Kubernetes master component.
 - 3 etcd 
 - 2 masters
 - 3 minions
 - VIP

The scripts, and playbooks are written to installing the Kubernetes Cluster for the Indigo Project with all the installed add-ons on Base Operation System: Fedora 23.
It's written to install a Kubernetes Cluster with 2 Master Server, and with N piece of LoadBalancer and Node Servers.

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

## Usage
* Pull the repositoy to your installer Machine
* Adjust the setup.conf with the necessary parameters. Example: LB_IP=1.2.3.4 You can extend the list of the servers as much as you need. If you don't have/need any kind of informations, which is listed in file just delete the line.
* Run setup.sh command

#### Known and open issues

