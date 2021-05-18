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
    wireless_sha="$(sudo sha256sum /etc/config/wireless)"
    netboot_sha="$(sudo sha256sum /etc/config/netboot)"
    overlay_sha="$(find "$BASE_DIR"/rootfs/overlay/$ID "$BASE_DIR"/rootfs/overlay/common -type f -exec sha256sum \{\} \; 2> /dev/null | sort)"
    echo "$(cat "$BASE_DIR"/rootfs/rootfs.tar.gz.sha256)" "$wireless_sha" "$netboot_sha" "$overlay_sha" | sha256sum
    mkdir -p /tmp/turris-netboot-status/ 2> /dev/null
    date +%s > /tmp/turris-netboot-status/"$ID"
}

setup() {
    SSID="$(sudo uci -q get wireless.@wifi-iface[0].ssid)"
    KEY="$(sudo uci -q get wireless.@wifi-iface[0].key)"
    COUNTRY="$(sudo uci -q get wireless.@wifi-device[0].country)"
    {
        echo '#!/bin/sh'
        echo 'cat > /etc/config/netboot << EOF'
        sudo cat /etc/config/netboot
        echo EOF
        echo

        if [ -f "$BASE_DIR"/rootfs/setup.sh ]; then
            cat "$BASE_DIR"/rootfs/setup.sh
        else
            cat /usr/share/turris-netboot/setup.sh
            cat "$BASE_DIR"/rootfs/postsetup.sh 2> /dev/null
        fi
        cat "$BASE_DIR"/rootfs/postsetup-$ID.sh 2> /dev/null
    } | sed -e 's|@@SSID@@|'"$SSID|" -e 's|@@KEY@@|'"$KEY|" -e 's|@@COUNTRY@@|'"$COUNTRY|" 
}

comm=""
read comm
case "$comm" in
    get_root) get_root ;;
    get_root_overlay) get_root_overlay ;;
    get_remote_access) tar -cf - --owner=root -C "$BASE_DIR"/clients/accepted/$ID remote ;;
    get_root_version) get_root_version ;;
    status)   echo "registered" ;;
    get_id)   echo "$ID" ;;
    get_version)   echo "$ID" ;;
    get_aes)  cat "$BASE_DIR"/clients/accepted/$ID/aes | hexdump -e '4/4 "%02x "' ;;
    get_timeout)  uci -q get netboot.setup.timeout || echo 20 ;;
    get_retry)  uci -q get netboot.setup.retry || echo 3 ;;
    setup)  setup ;;
    *) echo "Unknown command" ;;
esac
