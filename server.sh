#!/bin/sh
BASE_DIR="$HOME"

get_root_overlay() {
    mkdir -p "$BASE_DIR"/rootfs/overlay/common
    mkdir -p "$BASE_DIR"/rootfs/overlay/$ID
    if [ -f "$BASE_DIR"/rootfs/overlay/$ID.tar ]; then
        cat "$BASE_DIR"/rootfs/overlay/$ID.tar
    else
        tar -cf - --owner=root -C "$BASE_DIR"/rootfs/overlay/$ID . -C "$BASE_DIR"/rootfs/overlay/common .
    fi
}

get_root() {
    cat "$BASE_DIR"/rootfs/rootfs.tar.gz
}

get_root_version() {
    find /etc/config/wireless /etc/config/netboot "$BASE_DIR"/rootfs/overlay/$ID "$BASE_DIR"/rootfs/overlay/common -type f -exec sha256sum \{\} \; 2> /dev/null \
    | sort | \
    cat - "$BASE_DIR"/rootfs/rootfs.tar.gz.sha256 | sha256sum
}

setup() {
    SSID="$(uci -q get wireless.@wifi-iface[0].ssid)"
    KEY="$(uci -q get wireless.@wifi-iface[0].key)"
    {
        echo '#!/bin/sh'
        echo 'cat > /etc/config/netboot << EOF'
        cat /etc/config/netboot
        echo EOF
        echo

        if [ -f "$BASE_DIR"/rootfs/setup.sh ]; then
            cat "$BASE_DIR"/rootfs/setup.sh
        else
            cat /usr/share/turris-netboot/setup.sh
            cat "$BASE_DIR"/rootfs/postsetup.sh 2> /dev/null
        fi
        cat "$BASE_DIR"/rootfs/postsetup-$ID.sh 2> /dev/null
    } | sed -e 's|@@SSID@@|'"$SSID|" -e 's|@@KEY@@|'"$KEY|"
}

comm=""
read comm
case "$comm" in
    get_root) get_root ;;
    get_root_overlay) get_root ;;
    get_root_version) get_root_version ;;
    status)   echo "registered" ;;
    get_id)   echo "$ID" ;;
    get_version)   echo "$ID" ;;
    get_aes)  cat "$BASE_DIR"/clients/accepted/$ID/aes | hexdump -e '4/4 "%02x "' ;;
    get_timeout)  uci -q get netboot.setup.timeout || echo 60 ;;
    setup)  setup ;;
    *) echo "Unknown command" ;;
esac
