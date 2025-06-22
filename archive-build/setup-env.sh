#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <arch> <series> <install dependencies>" 
    exit 1
fi

if [ "$1" = "amd64" ]; then
    arch="amd64"
elif [ "$1" = "arm64" ]; then
    arch="arm64"
else
    echo "Invalid architecture: $1"
fi

if [ "$3" = "yes" ]; then
    echo "Install packages"
    sudo apt update
    sudo apt install -y sbuild schroot debootstrap debhelper devscripts equivs
    echo "Setup sbuild user"
    sudo usermod -aG sbuild "$USER"
fi

echo "Setup $arch sbuild root for $2"
if [ "$arch" = "amd64" ]; then
    repo="http://archive.ubuntu.com/ubuntu/"
elif [ "$arch" = "arm64" ]; then
    repo="http://ports.ubuntu.com/ubuntu-ports/"
else
    echo "Invalid architecture: $arch"
fi
sudo sbuild-createchroot --arch="$arch" "$2" /home/ubuntu/sbuild-root-"$2" "$repo"

if [ "$3" = "yes" ]; then
    echo "Copy sbuild.conf"
    sudo cp -f sbuild.conf /etc/schroot/chroot.d/
fi

if [ "$2" = "focal" ]; then
    if [ "$arch" = "amd64" ]; then
        sudo schroot -c focal -- bash -c "echo 'deb http://archive.ubuntu.com/ubuntu focal restricted universe multiverse' >> /etc/apt/sources.list"
        sudo schroot -c focal -- bash -c "echo 'deb-src http://archive.ubuntu.com/ubuntu focal restricted universe multiverse' >> /etc/apt/sources.list"
    elif [ "$arch" = "arm64" ]; then
        sudo schroot -c focal -- bash -c "echo 'deb http://ports.ubuntu.com/ubuntu-ports focal restricted universe multiverse' >> /etc/apt/sources.list"
        sudo schroot -c focal -- bash -c "echo 'deb-src http://ports.ubuntu.com/ubuntu-ports focal restricted universe multiverse' >> /etc/apt/sources.list"
    else
        echo "Invalid architecture: $arch"
    fi
    sudo schroot -c focal -- apt update
    sudo schroot -c focal -- apt install -y gcc-9 g++-9 gcc-10 g++-10
    sudo schroot -c focal -- update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 9
    sudo schroot -c focal -- update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo schroot -c focal -- update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 9
    sudo schroot -c focal -- update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
    sudo schroot -c focal -- update-alternatives --config gcc
    sudo schroot -c focal -- update-alternatives --config g++
    if [ "$arch" = "amd64" ]; then
        sudo cp amd64-focal.sources /etc/apt/sources.list.d/
    elif [ "$arch" = "arm64" ]; then
        sudo bash -c "echo 'deb http://ports.ubuntu.com/ubuntu-ports focal universe multiverse restricted main' >> /etc/apt/sources.list"
        sudo bash -c "echo 'deb-src http://ports.ubuntu.com/ubuntu-ports focal universe multiverse restricted main' >> /etc/apt/sources.list"
    else
        echo "Invalid architecture: $arch"
    fi
fi
if [ "$2" = "jammy" ]; then
    if [ "$arch" = "amd64" ]; then
        sudo schroot -c jammy -- bash -c "echo 'deb http://archive.ubuntu.com/ubuntu jammy restricted universe multiverse' >> /etc/apt/sources.list"
        sudo schroot -c jammy -- bash -c "echo 'deb-src http://archive.ubuntu.com/ubuntu jammy restricted universe multiverse' >> /etc/apt/sources.list"
    elif [ "$arch" = "arm64" ]; then
        sudo schroot -c jammy -- bash -c "echo 'deb http://ports.ubuntu.com/ubuntu-ports jammy restricted universe multiverse' >> /etc/apt/sources.list"
        sudo schroot -c jammy -- bash -c "echo 'deb-src http://ports.ubuntu.com/ubuntu-ports jammy restricted universe multiverse' >> /etc/apt/sources.list"
    else
        echo "Invalid architecture: $arch"
    fi
    sudo schroot -c jammy -- apt update
    sudo schroot -c jammy -- apt install -y gcc-10 g++-10 gcc-11 g++-11 gcc-12 g++-12
    sudo schroot -c jammy -- update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 10
    sudo schroot -c jammy -- update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10
    sudo schroot -c jammy -- update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 11
    sudo schroot -c jammy -- update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 11
    sudo schroot -c jammy -- update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 12
    sudo schroot -c jammy -- update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 12
    sudo schroot -c jammy -- update-alternatives --config gcc
    sudo schroot -c jammy -- update-alternatives --config g++
    if [ "$arch" = "amd64" ]; then
        sudo cp amd64-jammy.sources /etc/apt/sources.list.d/
    elif [ "$arch" = "arm64" ]; then
        sudo bash -c "echo 'deb http://ports.ubuntu.com/ubuntu-ports jammy universe multiverse restricted main' >> /etc/apt/sources.list"
        sudo bash -c "echo 'deb-src http://ports.ubuntu.com/ubuntu-ports jammy universe multiverse restricted main' >> /etc/apt/sources.list"
    else
        echo "Invalid architecture: $arch"
    fi
fi
sudo apt update

echo "Sbuild setup complete, please logout and login to start building"
