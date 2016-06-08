#!/bin/bash
################################################
## Setup Script for Indigo Kubernetes Cluster ##
##   with N etcd, 2 Master, and N Minion and  ##
##          N  HaProxy Loadbalancer           ##
################################################

main(){
#Ensure, that ansible is installed on the installer machine
rpm -qa | grep -qw ansible || dnf install ansible -y
 if [ $? != 0 ]
 then
   echo -en $COL_RED
   echo  "ERROR: Ansible can't be installed on this VM. Please check"
   echo -en $COL_NORMAL
   exit 1
 else
   echo -en $COL_INFO
   echo "INFO: Ansible installed, Continue check Cluster Servers"
   echo -en $COL_NORMAL
 fi

#Check, that all the servers reachable via SSH
for i in `cat setup.conf | grep 'LB\|ETCD\|MASTER\|NODE'  | cut -d"=" -f2| awk '{print $1}' | sort | uniq`
do
 ssh -q root@$i exit
 if [ $? != 0 ]
 then
   echo -en $COL_RED
   echo "ERROR: Login to $i not possible, program will exit"
   echo -en $COL_NORMAL
   exit 1
 fi
done

if [ $? -eq 0 ]
then 
  echo -en $COL_INFO
  echo "INFO: All Server are reachable. Start with the Prerequisite installations"
  echo -en $COL_NORMAL
fi

# Prereqisite on all servers
for i in `cat setup.conf | grep 'LB\|ETCD\|MASTER\|NODE'  | cut -d"=" -f2| awk '{print $1}' | sort | uniq`
do
  echo -en $COL_INFO
  echo "INFO: Preconfiguration of $i"
  echo -en $COL_NORMAL
  ssh root@$i 'dnf install python git python-netaddr python-dnf libselinux-python wget -y' &> /dev/null
 if [ $? != 0 ]
 then
   echo -en $COL_RED
   echo "ERROR: Required Packages can't install on $i. Program will exit"
   echo -en $COL_NORMAL
   exit 1
 fi
done

if [ $? -eq 0 ]
then
  echo -en $COL_INFO
  echo "INFO: Required Packages installed successfully. Setting up LoadBalancer Server Parameters"
  echo -en $COL_NORMAL
fi

for i in `cat setup.conf | grep LB | cut -d"=" -f2 | cut -d" " -f1`
do
  echo -en $COL_INFO
  echo "INFO: Setting sysctl parameter, and selinux for haproxy on $i"
  ssh root@$i 'echo net.ipv4.ip_nonlocal_bind=1 > /etc/sysctl.conf;sysctl -p &> /dev/null;setsebool -P haproxy_connect_any=1'
done

if [ $? -eq 0 ]
then
  echo -en $COL_INFO
  echo "INFO: Prerequisites Successfully done. Start the preconfiguration of LoadBalancer playbook"
  echo -en $COL_NORMAL
fi

# Installation of Loadbalancers
echo -en $COL_INFO
echo "INFO: Installing Loadbalancer services"
echo -en $COL_NORMAL
cat <<END >ha-lb/inventory
[lbs]
`cat setup.conf | grep LB | cut -d"=" -f2,3`

[vip]
`cat setup.conf | grep VIP | cut -d"=" -f2`
END

echo -en $COL_CYAN
echo "DEBUG: LB playbook inventory rewrited to the following:"
echo -en $COL_NORMAL
cat ha-lb/inventory
read -r -p "ACT: Please check Inventory config. Do you want to proceed with LB setup? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
	loadbalancer_setup
        ;;
    *)
        kubernetes_prereq
        ;;
esac
}

loadbalancer_setup(){
set +e
ansible-playbook -i ha-lb/inventory ha-lb/site.yaml
set -e
kubernetes_prereq
}

kubernetes_prereq(){
echo -en $COL_INFO
echo "INFO: Preparing Kubernetes Cluster Playbook"
echo -en $COL_NORMAL
for i in `grep -R 90.147.170.172 ha-kubernetes/ansible/roles/* | cut -d":" -f1`; do  sed -i s/90.147.170.172/`cat setup.conf | grep VIP | cut -d"=" -f2`/g $i; done
for i in `grep -R 90.147.170.120 ha-kubernetes/ansible/roles/* | cut -d":" -f1`; do  sed -i s/90.147.170.120/`cat setup.conf | grep MASTER1 | cut -d"=" -f2`/g $i; done
for i in `grep -R 90.147.170.119 ha-kubernetes/ansible/roles/* | cut -d":" -f1`; do  sed -i s/90.147.170.119/`cat setup.conf | grep MASTER2 | cut -d"=" -f2`/g $i; done

echo -en $COL_INFO
echo "INFO: Install Kubernetes Cluster with the first Master Server"
echo -en $COL_NORMAL
cat <<END >ha-kubernetes/ansible/inventory.ha
[masters]
$MASTER1

[etcd]
`cat setup.conf | grep ETCD | cut -d"=" -f2`

[nodes]
`cat setup.conf | grep NODE | cut -d"=" -f2`
END
echo -en $COL_CYAN
echo "DEBUG: Kubernetes playbook inventory rewrited to the following:"
echo -en $COL_NORMAL
cat ha-kubernetes/ansible/inventory.ha


read -r -p "ACT: Please check Inventory config. Do you want to proceed with Kubernetes setup with the 1st Master? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
	kubernetes_install
	;;
    *)
	echo -en $COL_RED
	echo "Installation interrupted"
	echo -en $COL_NORMAL
        exit 1
        ;;
esac
}

kubernetes_install(){
set +e
cd ./ha-kubernetes/ansible
INVENTORY=inventory.ha ./setup.sh
cd -
set -e

echo -en $COL_CYAN
echo "DEBUG: Kubernetes installation with 1st Master done. Please check the logs."
echo -en $COL_NORMAL
read -r -p "ACT: Do you want to start the 2nd Master installation? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
        kubernetes_2_prereq
        ;;
    *)
	cinder_setup_question
        ;;
esac
}
kubernetes_2_prereq(){
echo -en $COL_INFO
echo "INFO: Start the preparation for installing of Kubernetes Cluster 2nd Master"
echo -en $COL_NORMAL
ssh root@$MASTER2 'mkdir -p /etc/kubernetes/certs' 
ssh root@$MASTER1 'cd /etc/kubernetes/certs/;tar -zcvf certs.tgz *;mv certs.tgz /root/ &> /dev/null'
scp root@$MASTER1:/root/certs.tgz .
scp certs.tgz root@$MASTER2:/etc/kubernetes/certs/
ssh root@$MASTER2 'cd /etc/kubernetes/certs;tar -zxvf certs.tgz; rm -f certs.tgz &> /dev/null'
rm -f certs.tgz

echo -en $COL_CYAN
echo "DEBUG: 2nd Master cert directory content:"
echo -en $COL_NORMAL
ssh root@$MASTER2 'ls -l /etc/kubernetes/certs'

echo -en $COL_INFO
echo "INFO: Rewriting Inventory to install the 2nd node"
echo -en $COL_NORMAL
sed -i s/$MASTER1/$MASTER2/g ha-kubernetes/ansible/inventory.ha

echo -en $COL_CYAN
echo "DEBUG: Kubernetes playbook inventory rewrited to the following:"
echo -en $COL_NORMAL
cat ha-kubernetes/ansible/inventory.ha
read -r -p "ACT: Do you want to proceed? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
        kubernetes_2_install
        ;;
    *)
	echo -en $COL_RED
        echo "Installation interrupted"
	echo -en $COL_NORMAL
        exit 1
        ;;
esac
}
kubernetes_2_install(){
set +e
echo -en $COL_INFO
echo "INFO: Installing 2nd Master"
echo -en $COL_NORMAL

cd ha-kubernetes/ansible
INVENTORY=inventory.ha ./setup.sh --tags=masters
cd -
set -e

echo -en $COL_INFO
echo "INFO: Kubernetes successfully installed to the 2nd Master"
echo -en $COL_NORMAL

read -r -p "ACT: Please check install log. Do you want to continue? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
	cinder_setup_question
	;;
    *)
        echo -en $COL_RED
	echo "Aborted"
        echo -en $COL_NORMAL
        exit 1
        ;;
esac
}

cinder_setup_question(){
read -r -p "ACT: Do you want to configure Cinder Persistent Volume for Kubernetes Cluster? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
	cinder_setup
	;;
    *)
        lb_uservice_question
        ;;
esac
}

cinder_setup(){
echo -en $COL_INFO
echo "INFO: Start Cinder Persisten Volume management installation"
if `cat setup.conf | grep OPENSTACK_CA_URL`
then
  echo "INFO: Get OpenStack CA from vendor"
  echo -en $COL_NORMAL
  wget `cat setup.conf | grep OPENSTACK_CA_URL | cut -d"=" -f2` &> /dev/null
  CA_NAME=`cat setup.conf | grep OPENSTACK_CA_URL | cut -d"=" -f2 | rev | cut -d"/" -f1 | rev`
  if [ $? -eq 0 ]
  then
      echo -en $COL_INFO
      echo "INFO: Adding Certificate to the Kubernetes Servers"
      echo -en $COL_NORMAL
    for i in `cat setup.conf | grep 'MASTER\|NODE' | cut -d"=" -f2 | sort | uniq`
    do
      scp $CA_NAME root@$i:/root &> /dev/null
      ssh root@$i 'mv $CA_NAME /etc/pki/ca-trust/source/anchors/;update-ca-trust extract'
    done
  else
    echo -en $COL_WARN
    echo "WARN: Certificate can't be downloaded"
    echo -en $COL_NORMAL
  fi
  rm -f $CA_NAME
fi
echo -en $COL_INFO
echo "INFO: Creating cloud provider configuration file"
echo -en $COL_NORMAL
cat <<END >cloud.conf
[Global]
auth-url = `cat setup.conf | grep OPENSTACK_URL | cut -d"=" -f2`
username = `cat setup.conf | grep OPENSTACK_USER | cut -d"=" -f2`
password = `cat setup.conf | grep OPENSTACK_PASS | cut -d"=" -f2`
tenant-id = `cat setup.conf | grep OPENSTACK_TENANTID | cut -d"=" -f2`
region = `cat setup.conf | grep OPENSTACK_REGION | cut -d"=" -f2`
END

echo -en $COL_INFO
echo "INFO: Updating resolv.conf for proper name resulotion"
echo -en $COL_NORMAL

for i in `cat setup.conf | grep 'MASTER\|NODE' | cut -d"=" -f2 | sort | uniq`
do
  scp cloud.conf root@$i:/etc/cloud.conf &> /dev/null
  ssh root@$i 'cat <<END >/etc/resolv.conf
; generated by /usr/sbin/dhclient-script
search cloud.ba.infn.it
nameserver 192.135.10.4
nameserver 90.147.169.200
END'
done

rm -f cloud.conf
echo -en $COL_INFO
echo "INFO: Changing Configuration files on Master Servers"
echo -en $COL_NORMAL

echo -en $COL_CYAN
for i in `cat setup.conf | grep MASTER | cut -d"=" -f2`
do
  ssh root@$i "if grep -q openstack /etc/kubernetes/apiserver;then echo 'DEBUG: OpenStack Configuration already added to the APIServer Config. Nothing to do';else sed -ri 's/(KUBE_API_ARGS=\"[^\"]*)/\1 --cloud-config=\/etc\/cloud.conf --cloud-provider=openstack/' /etc/kubernetes/apiserver;service kube-apiserver restart &> /dev/null;fi;if grep -q openstack /etc/kubernetes/controller-manager;then echo 'DEBUG: OpenStack Configuration already added to the ControllerManager Config. Nothing to do';else sed -ri 's/(KUBE_CONTROLLER_MANAGER_ARGS=\"[^\"]*)/\1 --cloud-config=\/etc\/cloud.conf --cloud-provider=openstack/' /etc/kubernetes/controller-manager;service kube-controller-manager restart &> /dev/null;fi"
done

echo -en $COL_INFO
echo "INFO: Changing Configuration files on the Nodes"
echo -en $COL_CYAN
for i in `cat setup.conf | grep NODE | cut -d"=" -f2`
do
  ssh root@$i "if grep -q openstack /etc/kubernetes/kubelet; then echo 'DEBUG: OpenStack Configuration already added to the Kubelet Config. Changing only hostname configuration'; else  sed -ri 's/(KUBELET_ARGS=\"[^\"]*)/\1 --cloud-config=\/etc\/cloud.conf --cloud-provider=openstack/' /etc/kubernetes/kubelet; fi"
  ssh root@$i 'sed -ri "s/(hostname-override=).*(\")/\1`hostname -s`\2/g" /etc/kubernetes/kubelet;service kubelet restart &> /dev/null'
done
echo -en $COL_INFO
echo "INFO: Waiting for everything restarting properly"
echo -en $COL_NORMAL
sleep 30

MASTER1=`cat setup.conf | grep MASTER | cut -d"=" -f2 | head -1`
VIP=`cat setup.conf | grep VIP | cut -d"=" -f2`
TOKEN=`ssh root@$MASTER1 "cat /etc/kubernetes/tokens/system\:kubectl-$VIP.token"`
echo -en $COL_INFO
echo "INFO: Checking Node Status"
echo -en $COL_NORMAL
kubectl -s https://$VIP:8443 --user="kubectl" --token="$TOKEN"  --insecure-skip-tls-verify=true get node

read -r -p "ACT: Do you want to delete the Not Ready Nodes from the Cluster? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
       for i in  `kubectl -s https://$VIP:8443 --user="kubectl" --token="$TOKEN"  --insecure-skip-tls-verify=true get node |grep "NotReady" | awk '{print $1}'`
	do
	 kubectl -s https://$VIP:8443 --user="kubectl" --token="$TOKEN"  --insecure-skip-tls-verify=true delete node $i 
	done
       kubectl -s https://$VIP:8443 --user="kubectl" --token="$TOKEN"  --insecure-skip-tls-verify=true get node
        ;;
    *)
	echo -en $COL_RED
        echo "ERROR: Loadbalancer Service can't be installed with Not Ready Nodes"
	echo -en $COL_NORMAL
        exit 1
        ;;
esac
lb_uservice_question
}

lb_uservice_question(){
read -r -p "ACT: Do you want to setup LoadBalancer uService for Kubernetes Cluster? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
	lb_uservice_setup
        ;;
    *)
	echo "Installation Finished without LoadBalancer uService installation"
        exit 0
	break
        ;;
esac
}

lb_uservice_setup(){
MASTER1=`cat setup.conf | grep MASTER | cut -d"=" -f2 | head -1`
echo -en $COL_INFO
echo "INFO: Setting up LB uService"
echo "INFO: Labeling the first 2 Node to be member of loadbalancer service (error check missing)"
echo -en $COL_NORMAL
VIP=`cat setup.conf | grep VIP | cut -d"=" -f2`
TOKEN=`ssh root@$MASTER1 "cat /etc/kubernetes/tokens/system\:kubectl-$VIP.token"`
NODES=`kubectl -s https://$VIP:8443 --user="kubectl" --token="$TOKEN"  --insecure-skip-tls-verify=true get node | head -3 | tail -2 | awk '{print $1}'`
for i in $NODES
do
  kubectl -s https://$VIP:8443 --user="kubectl" --token="$TOKEN"  --insecure-skip-tls-verify=true label node $i role=loadbalancer  --overwrite
done

echo -en $COL_INFO
echo "INFO: Creating and copying certificate"
echo -en $COL_NORMAL
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx.key -out nginx.crt
cat nginx.crt nginx.key > nginx.pem 

for i in `cat setup.conf | grep NODE | cut -d"=" -f2`
do
  ssh root@$i 'mkdir -p /etc/nginx/ssl'
  scp nginx.pem root@$i:/etc/nginx/ssl/ &> /dev/null
done

echo -en $COL_INFO
echo "INFO: Creating secret.yaml"
echo -en $COL_NORMAL
wget https://raw.githubusercontent.com/indigo-dc/kubernetes/master/ha-kubernetes/ansible/roles/kubernetes-addons/files/make-cert.sh
./make-cert.sh nginxsecret secret.yaml nginx.key nginx.crt 
rm -f nginx.*

echo -en $COL_INFO
echo "INFO: Download service files, and add to the cluster"
echo -en $COL_NORMAL
for i in `cat setup.conf | grep MASTER | cut -d"=" -f2`
do
 ssh root@$i 'mkdir -p /etc/kubernetes/addons/lb;cd /etc/kubernetes/addons/lb;wget https://raw.githubusercontent.com/indigo-dc/kubernetes/master/ha-kubernetes/ansible/roles/kubernetes-addons/files/lb/lb-rc.yaml &> /dev/null;wget https://raw.githubusercontent.com/indigo-dc/kubernetes/master/ha-kubernetes/ansible/roles/kubernetes-addons/files/lb/lb-svc.yaml &> /dev/null'
done

for i in `cat setup.conf | grep MASTER | cut -d"=" -f2`
do 
  scp secret.yaml root@$i:/etc/kubernetes/addons/lb &> /dev/null
done
rm -f secret.yaml

ssh root@$MASTER1 'kubectl create -f /etc/kubernetes/addons/lb/secret.yaml;kubectl create -f /etc/kubernetes/addons/lb/lb-rc.yaml;kubectl create -f /etc/kubernetes/addons/lb/lb-svc.yaml'
echo "All Choosen Service installed successfully. Enjoy to use the Cluster"
}
COL_INFO='\E[32;40m'
COL_RED='\E[31;40m'
COL_NORMAL='\E[37;40m'
COL_WARN='\E[33;40m'
COL_CYAN='\E[36m'

set -e
MASTER1=`cat setup.conf | grep MASTER | cut -d"=" -f2 | head -1`
MASTER2=`cat setup.conf | grep MASTER | cut -d"=" -f2 | tail -1`
export MASTER1
export MASTER2

main
