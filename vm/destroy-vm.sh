#!/bin/bash

vm_name="$1"

if [ -z "$vm_name" ]; then
        echo "please specify VM name"
        exit 1
fi

virsh shutdown "$vm_name"
virsh undefine "$vm_name"
rm -f "$vm_name".img cloud-init-"$vm_name".iso
