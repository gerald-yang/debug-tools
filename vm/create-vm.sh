#!/bin/bash

function print_usage {
        echo "Usage:"
        echo "./create-vm.sh {vm name} {ubuntu series} {vm vcpu} {vm ram in MB} {vm image size}"
        echo ""
        echo "example:"
        echo "./create-vm.sh testvm xenial 4 16384 30G"
        echo ""
}

function check_dep {
        pkglist=("virt-manager" "qemu-system-x86" "cloud-image-utils")

        echo "checking dependencies"
        for pkg in ${pkglist[@]}; do
                pkg_install=$(dpkg -l | grep "$pkg")
                if [ -z "$pkg_install" ]; then
                        echo "$pkg not installed"
                        sudo apt install -y $pkg
                        echo "you may need to reboot the machine before creating VM"
                fi
        done
        echo "all dependencies are installed"
}

function download_image {
        if [ -f "$2" ]; then
                echo "image already downloaded"
        else
                echo "downloading image"
                wget https://cloud-images.ubuntu.com/"$1"/current/"$2"
        fi
}

function create_vm_image {
        cp "$2" "$1".img
        qemu-img resize "$1".img "$3"
}

function create_cloud_init {
        echo "#cloud-config" > cloud.cfg
        echo "password: 1234" >> cloud.cfg
        echo "chpasswd: { expire: False }" >> cloud.cfg
        echo "ssh_pwauth: True" >> cloud.cfg
        echo "hostname: $1" >> cloud.cfg

        cloud-localds cloud-init-"$1".iso cloud.cfg
}

function launch_vm {
        virt-install -n "$1" --description "test vm" --os-type generic --vcpu "$2" --ram "$3" --disk "$1".img,device=disk,bus=virtio,cache=directsync --disk cloud-init-"$1".iso,device=cdrom --virt-type kvm --graphics none --network network=default,model=virtio --import --noautoconsole
        #virsh list
}

function setup_ssh_config {
        echo "setup ssh config"
        while true; do
                net_created=$(virsh domifaddr "$1" | grep vnet)
                if [ -z "$net_created" ]; then
                        echo "waiting for network"
                        sleep 3
                else
                        break
                fi
        done
        ipaddr=$(virsh domifaddr "$1" | grep vnet | awk '{print $4}' | cut -d '/' -f 1)
        
        if ! [ -f ~/.ssh/config ]; then
                echo "generate ssh config file"
                echo "# Generate for test VMs" > ~/.ssh/config
        fi

        if grep -q "Host $1$" ~/.ssh/config ; then
                echo "config exists, changing it"
                orig_ipaddr=$(grep -A 4 "Host $1$" ~/.ssh/config | grep HostName | awk '{print $2}')
                sed -i "s/$orig_ipaddr/$ipaddr/g" ~/.ssh/config
        else
                echo "create a config for $1"
                echo "" >> ~/.ssh/config
                echo "Host $1" >> ~/.ssh/config
                echo "  ForwardAgent yes" >> ~/.ssh/config
                echo "  HostName $ipaddr" >> ~/.ssh/config
                echo "  User ubuntu" >> ~/.ssh/config
        fi
}


#xenial_image="xenial-server-cloudimg-amd64-disk1.img"
#bionic_image="bionic-server-cloudimg-amd64.img"
#focal_image="focal-server-cloudimg-amd64.img"
#jammy_image="jammy-server-cloudimg-amd64.img"

vm_name="$1"
vm_series="$2"
vm_cpus="$3"
vm_mem="$4"
vm_size="$5"

if [ -z "$vm_name" ] || [ -z "$vm_series" ] || [ -z "$vm_cpus" ] || [ -z "$vm_mem" ] || [ -z "$vm_size" ]; then
        print_usage
        exit 1
fi

if [ "$vm_series" = "xenial" ]; then
        ubuntu_image="xenial-server-cloudimg-amd64-disk1.img"
else
        ubuntu_image="$vm_series-server-cloudimg-amd64.img"
fi


check_dep
download_image "$vm_series" "$ubuntu_image"
create_vm_image "$vm_name" "$ubuntu_image" "$vm_size"
create_cloud_init "$vm_name"
launch_vm "$vm_name" "$vm_cpus" "$vm_mem"
setup_ssh_config "$vm_name"

