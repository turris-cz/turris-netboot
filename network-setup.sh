#!/bin/sh
uci set network.lan.ifname="$(cd /sys/class/net/; ls -1 eth* lan* | tr '\n' ' ')"
uci set network.lan.proto='dhcp'
uci set network.lan.force_link='1'
uci set network.lan.type='bridge'
uci set network.wan.ifname=''
uci delete network.lan.ipaddr
uci delete network.lan.netmask
uci delete network.lan.ip6assign
wifi detect
for i in $(uci show wireless | sed -n 's|.*\.\(@wifi-iface[^.]*\)=.*|\1|p'); do
    uci set wireless.$i.ssid="@@SSID@@"
    uci set wireless.$i.encryption='psk2+ccmp'
    uci set wireless.$i.key="@@KEY@@"
    uci set wireless.$i.disabled="0"
    uci set wireless.$i.network="lan"
done
uci commit
/etc/init.d/network restart
