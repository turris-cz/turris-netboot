#!/bin/sh

# this script will deploy netboot files to host router (netboot has to be installed there)

set -e
set -x

ROUTER_IP=${ROUTER_IP:-192.168.1.1}
NETBOOT_WORK_DIR=${NETBOOT_WORK_DIR:-/srv/turris-netboot}
ORIG_DIR="$(pwd)"

# update files from package
scp server.sh root@${ROUTER_IP}:/usr/bin/netboot-server
scp manage.sh root@${ROUTER_IP}:/usr/bin/netboot-manager
scp setup.sh root@${ROUTER_IP}:/usr/bin/netboot-setup
scp encrypt.py root@${ROUTER_IP}:/usr/bin/netboot-encrypt
scp network-setup.sh root@${ROUTER_IP}:/usr/share/turris-netboot/setup.sh
scp set-static-lease.py root@${ROUTER_IP}:/usr/bin/netboot-set-static-lease

# inject rescue.sh into image
mkdir -p /tmp/netboot-repack
cd /tmp/netboot-repack/
scp root@${ROUTER_IP}:${NETBOOT_WORK_DIR}/rootfs/rootfs.tar.gz .
sudo tar xzf rootfs.tar.gz
sudo rm rootfs.tar.gz
cd usr/share/turris-netboot
sudo mkdir unpack
cd unpack
sudo cpio -i < ../initrd-aarch64
sudo cp "$ORIG_DIR"/rescue.sh init
sudo bash -c 'find | sudo cpio -o -H newc > ../initrd-aarch64'
cd /tmp/netboot-repack/
sudo rm -rf usr/share/turris-netboot/unpack
sudo tar czf rootfs.tar.gz ./*

# copy modified image and force tftp image redeploy
scp /tmp/netboot-repack/rootfs.tar.gz root@${ROUTER_IP}:${NETBOOT_WORK_DIR}/rootfs/rootfs.tar.gz
ssh root@${ROUTER_IP} /usr/bin/netboot-manager get_rootfs

# cleanup 
sudo rm -rf /tmp/netboot-repack/
