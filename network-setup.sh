#!/bin/sh
SERIAL="$(cat /sys/devices/platform/soc/soc:internal-regs@d0000000/soc:internal-regs@d0000000:crypto@0/mox_serial_number)"
uci set network.lan.ifname="$(cd /sys/class/net/; ls -1d eth* lan* | tr '\n' ' ')"
uci set network.lan.proto='dhcp'
uci set network.lan.macaddr='$(cat /sys/class/net/eth0/address)'
uci set network.lan.force_link='1'
uci set network.lan.type='bridge'
uci set network.wan.ifname=''
uci delete network.lan.ipaddr
uci delete network.lan.netmask
uci delete network.lan.ip6assign
uci commit
/etc/init.d/network restart
RADIO=0

get_option() {
    RES="$(uci -q get netboot.${SERIAL}_$WIFIID.$1)"
    [ -n "$RES" ] || RES="$(uci -q get netboot.$SERIAL.$1)"
    [ -n "$RES" ] || RES="$(uci -q get netboot.$WIFIID.$1)"
    [ -n "$RES" ] || RES="$(uci -q get netboot.$DEF.$1)"
    [ -n "$RES" ] || RES="$2"
    [ -z "$RES" ] || echo "$RES"
}

random() {
    MOD="$1"
    [ -n "$MOD" ] || MOD=65536
    echo $(expr $(printf '%d' 0x$(head -c 2 /dev/urandom | hexdump -e '"%02x"')) % $MOD)
}

for wifi in $(cd /sys/class/ieee80211; ls -1d phy*); do
    [ -d "/sys/class/ieee80211/$wifi" ] || continue
    VENDOR="$(cat /sys/class/ieee80211/$wifi/device/vendor | sed 's|^0x||')"
    MODEL="$(cat /sys/class/ieee80211/$wifi/device/device  | sed 's|^0x||')"
    MAC="$(cat /sys/class/ieee80211/$wifi/addresses)"
    WIFIID="${VENDOR}_$MODEL"

    DEF="$(get_option network default)"
    SSID="$(get_option ssid @@SSID@@)"
    KEY="$(get_option key @@KEY@@)"
    CHANNEL="$(get_option channel auto24)"
    HTMODE="$(get_option htmode)"
    COUNTRY="$(get_option country @@COUNTRY@@)"
    if [ "$CHANNEL" = auto24 ]; then
        CHANNEL="$(random 12)"
    fi
    if [ "$CHANNEL" = auto5 ]; then
        CHANNEL="$(random 18)"
        if [ "$CHANNEL" -gt 7 ]; then
            CHANNEL="$(expr 72 + "$CHANNEL" \* 4)"
        else
            CHANNEL="$(expr 36 + "$CHANNEL" \* 4)"
        fi
    fi

    if [ "$CHANNEL" -gt 13 ]; then
        HWMODE="11a"
        [ -n "$HTMODE" ] || HTMODE=VHT80
    else
        HWMODE="11g"
        [ -n "$HTMODE" ] || HTMODE=HT40
    fi
    cat << EOF
config wifi-device 'radio$RADIO'
        option type 'mac80211'
        option channel '$CHANNEL'
        option hwmode '$HWMODE'
        option macaddr '$MAC'
        option htmode '$HTMODE'
        option country '$COUNTRY'
        option disabled '0'

config wifi-iface 'default_radio$RADIO'
        option device 'radio$RADIO'
        option network 'lan'
        option mode 'ap'
        option ssid '$SSID'
        option key '$KEY'
        option encryption 'psk2+ccmp'
        option disabled '0'

EOF
    RADIO="$(expr "$RADIO" + 1)"
done > /etc/config/wireless
/etc/init.d/network restart
