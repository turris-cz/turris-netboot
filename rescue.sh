#!/bin/sh
die() {
    echo "$@"
    exit 1
}

SSH_OPTS="-o BatchMode=yes -o HostKeyAlgorithms=ssh-ed25519 -o HashKnownHosts=no -o UserKnownHostsFile=/root/.ssh/known_hosts"

configure_fosquitto() {
    cat > "$1/etc/config/fosquitto" <<- EOM

config global 'global'
	option debug '0'

config local 'local'
	option port '11883'

config remote 'remote'
	option port '11884'
	option enabled '1'
EOM
}

get_reg_keys() {
    mkdir -p /root/.ssh
    {
        echo '-----BEGIN OPENSSH PRIVATE KEY-----'
        cat /proc/cmdline | tr ' ' '\n' | \
        sed -n 's|^reg_key=||p' | sed 's|\(.\{70\}\)|\1\n|g'
        echo '-----END OPENSSH PRIVATE KEY-----'
    } > /root/.ssh/reg_key
    chmod 0600 /root/.ssh/reg_key
    cat /proc/cmdline |  tr ' ' \\n | \
    sed -n 's|^pub_key=|'"$SERVER_IP"' ssh-ed25519 |p' > /root/.ssh/known_hosts
}

my_netboot() {
    echo "$1" | ssh -i /root/.ssh/my_ssh_key $SSH_OPTS turris-netboot@"$SERVER_IP"
}

pair() {
    rm -f /root/.ssh/my_ssh_key*
    get_reg_keys
    ssh-keygen -t ed25519 -f /root/.ssh/my_ssh_key -N "" -C "${SERIAL}@${MAC}"
    cat /root/.ssh/my_ssh_key.pub \
        | ssh -i /root/.ssh/reg_key $SSH_OPTS turris-netboot@"$SERVER_IP" \
        || die "Can't connect to server to register"
    echo "Registered with following key:"
    echo
    cat /root/.ssh/my_ssh_key.pub
    echo
    echo -n "Waiting for registration to get accepted"
    while [ "$(my_netboot status 2> /dev/null)" \!= registered ]; do
        sleep 5
        echo -n .
    done
    echo
    echo "We are registered now!"
    ORIG="$(fw_printenv)"
    KEY_ADDR="$(printf %d 0x4d00000)"
    PXE_ADDR="$(printf %d 0x4e00000)"
    fw_setenv -s - << EOF
$ORIG
my_ssh_key=$(grep '^[^-]' /root/.ssh/my_ssh_key | tr '\n' ' ' | sed 's| ||g')
server_pub_key=$(cat /root/.ssh/known_hosts | head -n 1 | sed -n 's|.* ssh-ed25519 ||p')
key_addr=0x$(printf %x $KEY_ADDR)
bootargs=console=ttyMV0,115200 earlycon=ar3700_uart,0xd0012000
mox_net_get=dhcp \${pxefile_addr_r} /turris-netboot/mox_${SERIAL}; kernel_size=\$filesize;
mox_net_decrypt=aes dec 0x$(printf %x $KEY_ADDR) 0x$(printf %x $PXE_ADDR) 0x$(printf %x $(expr $PXE_ADDR + 16)) 0x8000000 \$kernel_size
mox_net_get_key=$(add=0; for i in $(my_netboot get_aes 2> /dev/null); do
    echo -n mw.q 0x$(printf %x $(expr $KEY_ADDR + $add '*' 4)) $i\; ;
    add=$(expr "$add" + 1);
done)
mox_net_run=bootm 0x8000000
mox_net_boot=run mox_net_get; run mox_net_get_key; run mox_net_decrypt; run mox_net_run
mox_boot=gpio clear GPIO221; if gpio input GPIO220 && sleep 1 && gpio input GPIO220; then run rescue_bootcmd; else run mox_net_boot; fi
bootcmd=run mox_boot
EOF
}

echo "Starting network boot!"

echo "Initializing the system"
mount -t sysfs none /sys
mount -t proc none /proc
mount -t devtmpfs devtmpfs /dev
mkdir /dev/pts
mount -t devpts devpts /dev/pts
mkdir -p /etc
echo '/dev/mtd2 0 0x00010000' > /etc/fw_env.config
SERIAL="$(cat /sys/bus/platform/devices/soc:internal-regs@d0000000:crypto@0/mox_serial_number)"
MAC="$(cat /sys/class/net/eth0/address)"

mkdir -p /root/.ssh
cat > /root/.ssh/my_ssh_key << EOF
-----BEGIN OPENSSH PRIVATE KEY-----
$(fw_printenv | sed -n 's|my_ssh_key=||p' | sed 's|\(.\{70\}\)|\1\n|g' )
-----END OPENSSH PRIVATE KEY-----
EOF
chmod 0600 /root/.ssh/my_ssh_key

while ! udhcpc -i eth0 -qfn; do
        echo "No DHCP :-("
        sleep 2
done

SERVER_IP="$(cat /proc/cmdline |  tr ' ' \\n | sed -n 's|^boot_server=||p')"
[ -n "$SERVER_IP" ] || SERVER_IP="$(ip r s | sed -n 's|default via \([^[:blank:]]*\)[[:blank:]].*|\1|p')"

grep -q '^[^-]' /root/.ssh/my_ssh_key || pair

fw_printenv | sed -n 's|server_pub_key=|'"$SERVER_IP"' ssh-ed25519 |p' > /root/.ssh/known_hosts

mkdir /chroot
my_netboot get_root | tar -C /chroot -xzvf - || die "Can't get rootfs"
my_netboot get_root_overlay 2> /dev/null | tar -C /chroot -xvf - 2> /dev/null || :
my_netboot get_root_version > /chroot/root-version
TIMEOUT="$(my_netboot get_timeout 2> /dev/null)"
[ -n "$TIMEOUT" ] || TIMEOUT=60
( sleep 120; while sleep $TIMEOUT; do [ "$(my_netboot get_root_version)" = "$(cat /chroot/root-version)" ] || reboot -f; done ) &
mkdir -p /chroot/etc/ssl/ca/remote
if my_netboot get_remote_access 2> /dev/null | tar -C /chroot/etc/ssl/ca -xvf - 2> /dev/null; then
	configure_fosquitto /chroot
else
	echo "Can't get remote access certs :-("
fi
my_netboot setup > /chroot/etc/rc.local
for i in sys proc dev dev/pts; do
    mount -o bind /$i /chroot/$i
done
exec chroot /chroot /sbin/init
