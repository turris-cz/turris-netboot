#!/bin/sh
uci set dhcp.@dnsmasq[0].enable_tftp=1
uci set dhcp.@dnsmasq[0].tftp_root='/srv/tftp'
mkdir -p /srv/tftp
uci commit
/etc/init.d/dnsmasq restart
grep -q '^turris-netboot:' /etc/passwd || useradd -md /srv/turris-netboot -s /bin/ash turris-netboot
usermod -p "$(head -c 100 /dev/urandom | hexdump -e '"%x"')" turris-netboot
usermod -U turris-netboot
chown -R turris-netboot /srv/turris-netboot
mkdir -p /srv/tftp/pxelinux.cfg
touch /srv/tftp/pxelinux.cfg/default-arm-mvebu-turris_mox
chown turris-netboot /srv/tftp/pxelinux.cfg/default-arm-mvebu-turris_mox
mkdir -p /srv/tftp/turris-netboot
chown turris-netboot /srv/tftp/turris-netboot
netboot-manager regen
