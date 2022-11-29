#!/bin/bash

deploy_init() {
        sudo apt update
        sudo apt install docker.io
        sudo systemctl enable docker
        sudo systemctl start docker
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
        sudo apt-add-repository "deb http://apt.kubernetes.io/kubernetes-xenial main"
        sudo apt-get install kubeadm kubelet kubectl
}

deploy_master() {
        NET="$1"
        NETMASK="$2"
        #sudo kubeadm init --pod-network-cidr=192.168.122.0/24
        sudo kubeadm init --pod-network-cidr="$NET"/"$NETMASK"
        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        sudo kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
}

worker_join() {
        echo "join command with token can be found from the output of 'kubeadm init'"
}

