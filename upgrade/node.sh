#!/bin/sh

NODE=90.147.102.63

scp kube-kubelet $NODE:/usr/bin/
scp kube-proxy $NODE:/usr/bin/

ssh $NODE 'chown kube. /usr/bin/kube*'
ssh $NODE 'chmod 770 /usr/bin/kube*'
