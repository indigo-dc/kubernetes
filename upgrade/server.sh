#!/bin/sh
MASTER=90.147.102.4

scp kube-apiserver $MASTER:/usr/bin/
scp kubectl $MASTER:/usr/bin/
scp kubelet $MASTER:/usr/bin/
scp kube-scheduler $MASTER:/usr/bin/
scp kube-controller-manager $MASTER:/usr/bin/

ssh $MASTER 'chown kube. /usr/bin/kube*'
ssh $MASTER 'chmod 770 /usr/bin/kube*'
