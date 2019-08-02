#!/bin/sh
. /usr/share/libubox/jshn.sh

BASE_DIR="$(echo ~turris-netboot)/clients"

CMD="$0"
ARGUMENTS="$@"

set_netboot_user() {
    args="${@:-$ARGUMENTS}"
    [ "$(id -un)" = turris-netboot ] || exec su turris-netboot -- "$CMD" $args
}


JSON=""
THIS_ID=$(/usr/bin/crypto-wrapper serial-number 2> /dev/null || echo "netboot_master")

die() {
    echo "$@" >&2
    exit 1
}

# Ensure serial number is in hexadecimal format, input can be either hexa or decimal
ensure_hexa() {
    # Decimal keys don't have leading zeros
    if expr "$1" : 000 > /dev/null; then
        echo "$1"
    else
        printf '%016X\n' "$1"
    fi
}

list() {
    cd "$BASE_DIR/$1"
    if [ -z "$JSON" ]; then
        echo "$1:" | sed -e 's|^a|A|' -e 's|^i|I|' -e 's|^t|T|'
    fi
    for i in */ssh_key; do
        [ -f "$i" ] || continue
        ID="$(printf '%d' "0x$(dirname "$i")")"
        if [ -z "$JSON" ]; then
            echo " * $ID"
        else
            json_add_string "$ID" "$ID"
        fi
    done
    if [ -z "$JSON" ]; then
        echo
    fi
    cd "$BASE_DIR"
}

get_rootfs() {
    set_netboot_user get_rootfs $1

    mkdir -p "$HOME"/rootfs/
    cd "$HOME"/rootfs/ || die "Can't cd to $HOME/rootfs/"
    if [ \! -f ./rootfs.tar.gz ] || [ "x$1" = "x-f" ]; then
        echo "Getting new rootfs..." >&2
        rm -f rootfs-new.tar.gz*
        wget -O "$HOME"/rootfs/rootfs-new.tar.gz https://repo.turris.cz/hbs/netboot/mox-netboot-latest.tar.gz || die "Can't download tarball"
        wget -O "$HOME"/rootfs/rootfs-new.tar.gz.sha256 https://repo.turris.cz/hbs/netboot/mox-netboot-latest.tar.gz.sha256 || die "Can't download checksum"
        wget -O "$HOME"/rootfs/rootfs-new.tar.gz.sig https://repo.turris.cz/hbs/netboot/mox-netboot-latest.tar.gz.sig || die "Can't download signature"
        sed -i 's|mox-netboot-.*|rootfs-new.tar.gz|' "$HOME"/rootfs/rootfs-new.tar.gz.sha256
        sha256sum -c ./rootfs-new.tar.gz.sha256 || {
            rm -f ./rootfs-new.tar.gz*
            die "Download failed"
        }
        usign -V -m ./rootfs-new.tar.gz -P /etc/opkg/keys/ || {
            rm -f ./rootfs-new.tar.gz*
            die "Tampered tarball"
        }
        sed -i 's|rootfs-new.tar.gz|rootfs.tar.gz|' "$HOME"/rootfs/rootfs-new.tar.gz.sha256
        mv "$HOME"/rootfs/rootfs-new.tar.gz "$HOME"/rootfs/rootfs.tar.gz
        mv "$HOME"/rootfs/rootfs-new.tar.gz.sha256 "$HOME"/rootfs/rootfs.tar.gz.sha256
        mv "$HOME"/rootfs/rootfs-new.tar.gz.sig "$HOME"/rootfs/rootfs.tar.gz.sig
    fi
    if [ ./rootfs.tar.gz -nt /srv/tftp/turris-netboot/mox ] || [ \! -f /srv/tftp/turris-netboot/mox ]; then
        cd "$HOME"/rootfs/
        rm -rf ./boot ./usr mox.its
        tar -xzf rootfs.tar.gz ./boot/Image ./boot/armada-3720-turris-mox.dtb ./usr/share/turris-netboot/initrd-aarch64 ./usr/share/turris-netboot/mox.its || die "Wrong rootfs"
        rm -f mox.its
        cp ./usr/share/turris-netboot/mox.its .
        /usr/sbin/mkimage -f mox.its /srv/tftp/turris-netboot/mox || die "Can't create image"
        rm -rf ./boot ./usr mox.its
    fi
}

update_rootfs() {
    set_netboot_user update_rootfs

    wget -O /tmp/rootfs-check.tar.gz.sha256 https://repo.turris.cz/hbs/netboot/mox-netboot-latest.tar.gz.sha256
    sed -i 's|mox-netboot-.*|rootfs.tar.gz|' /tmp/rootfs-check.tar.gz.sha256
    cd "$HOME"/rootfs/
    sha256sum -c /tmp/rootfs-check.tar.gz.sha256 || {
        get_rootfs -f
    }
    rm -f /tmp/rootfs-check.tar.gz.sha256
}

regen() {
    set_netboot_user regen $1

    cd "$BASE_DIR"/accepted
    echo "Regenerating configuration..." >&2
    [ -f ~/.ssh/reg_key.pub ] || ssh-keygen -t ed25519 -f ~/.ssh/reg_key -N "" -C "registration_key"
    if [ "x$1" = "x-f" ] || [ \! -f /srv/tftp/pxelinux.cfg/default-arm-mvebu-turris_mox ] || \
       [ ~/.ssh/reg_key -nt /srv/tftp/pxelinux.cfg/default-arm-mvebu-turris_mox ] || \
       grep -q 'reg_key=[^[:blank:]]' /srv/tftp/pxelinux.cfg/default-arm-mvebu-turris_mox; then
        cat > /srv/tftp/pxelinux.cfg/default-arm-mvebu-turris_mox << EOF
default pair
prompt 0
timeout 0

label pair
    kernel /turris-netboot/mox
    append reg_key=$(grep '^[^-]' ~/.ssh/reg_key | tr '\n' ' ' | sed 's| ||g') pub_key=$(ssh-keyscan localhost 2> /dev/null | sed -n 's|localhost ssh-ed25519 ||p') console=ttyMV0,115200 earlycon=ar3700_uart,0xd0012000
EOF
    fi
    {
    echo -n "no-agent-forwarding,no-port-forwarding,no-X11-forwarding,"
    echo -n "command=\"$MYSELF register\" "
    cat ~/.ssh/reg_key.pub
    for i in */ssh_key; do
        [ -f "$i" ] || continue
        echo -n "environment=\"ID=$(dirname "$i")\","
        echo -n "no-agent-forwarding,no-port-forwarding,no-X11-forwarding,"
        echo -n "command=\"export ID=$(dirname "$i"); $(dirname "$MYSELF")/netboot-server\" "
        cat "$i"
    done
    } > ~/.ssh/authorized_keys
    chmod 0644 ~/.ssh/authorized_keys
    get_rootfs $1
    cd "$BASE_DIR"/accepted
    echo "Signing kernels..." >&2
    for i in */aes; do
        [ -f "$i" ] || continue
        if [ /srv/tftp/turris-netboot/mox_$(dirname "$i") -ot /srv/tftp/turris-netboot/mox ] || \
           [ /srv/tftp/turris-netboot/mox_$(dirname "$i") -ot "$i" ] || \
           [ \! -f /srv/tftp/turris-netboot/mox_$(dirname "$i") ] || [ "x$1" = "x-f" ]; then
            netboot-encrypt /srv/tftp/turris-netboot/mox "$i" /srv/tftp/turris-netboot/mox_$(dirname "$i")
        fi
    done
}

generate_remote_access_certs() {
    CA_DIR="$1" /usr/bin/turris-cagen new_ca remote gen_ca gen_server turris gen_client "$THIS_ID-$2"
}

prepare_client_token() {
    local name="$THIS_ID-$1"
    local ip="$2"
    local tmp_dir="/tmp/netboot-tokens"
    local target_dir="$tmp_dir/$name/"
    local token_file="$tmp_dir/token-${name}.tar.gz"
    local msg_file="$tmp_dir/${name}.json"

    mkdir -p  "$target_dir"
    cp transfering/$1/remote/ca.crt "${target_dir}/ca.crt"
    cp transfering/$1/remote/02.crt "${target_dir}/token.crt"
    cp transfering/$1/remote/02.key "${target_dir}/token.key"

    # generate configuration json
    json_init
    json_add_string "name" "$name"
    json_add_string "hostname" "turris"
    json_add_int "port" 11884
    json_add_string "device_id" "$1"
    json_add_object "ipv4_ips"
        json_add_array "wan"
            json_add_string "$ip" "$ip"
        json_close_array
        json_add_array "lan"
        json_close_array
    json_close_object
    json_add_object "dhcp_names"
        json_add_string "lan" ""
        json_add_string "wan" ""
    json_close_object
    jshn -w > "${target_dir}/conf.json"
    tar czf "$token_file" -C "$tmp_dir" "$name"

    # call foris-controller
    json_init
    json_add_string "token" $(cat "$token_file" | base64 -w 0)
    jshn -w > "$msg_file"
    foris-client-wrapper -m subordinates -a add_sub -i "$msg_file"

    # set custom name to decadic serial for user friendliness
    uci set "foris-controller-subordinates.$1"="subordinate"
    uci set "foris-controller-subordinates.$1.custom_name"="$(printf %d "0x$1")"
    uci commit foris-controller-subordinates

    # Cleanup
    rm -rf  "$target_dir" "$token_file" "$msg_file"
}

accept() {
    # this should be run as root
    [ -d "incoming/$1" ] || exit 1
    rm -rf "accepted/$1" "transfering/$1"
    mv "incoming/$1" "transfering/$1"
    head -c 16 /dev/urandom > transfering/$1/aes
    local mac="$(cat "transfering/$1/mac")"
    if [ -n "$mac" ]; then
        # generate remote access CA and certificates (should create transfering/../remove dir)
        generate_remote_access_certs "transfering/$1" "$1"
        # store static lease
        local new_ip="$(netboot-set-static-lease "$1" "$mac" 2>/dev/null)"
        echo "IP address $new_ip was allocated for ${1} (${mac})"
        prepare_client_token "$1" "$new_ip"
        chown -R turris-netboot transfering/$1
    fi

    mv "transfering/$1" "accepted/$1"
    regen
}

revoke() {
    set_netboot_user

    [ -d "accepted/$1" ] || exit 1
    rm -rf "accepted/$1"
    foris-client-wrapper -m subordinates -a del -I "{\"controller_id\":\"$1\"}"
    regen
}

register() {
    set_netboot_user

    KEY="$(head -c 256 | grep '^ssh-ed25519 [a-zA-Z0-9/+=]\+ [0-9A-F@a-z:]\+$')"
    if [ "$KEY" ]; then
        SERIAL="$(echo "$KEY" | sed -n 's|.*\ \([0-9A-Z]\+\)@[0-9a-z:]\+$|\1|p')"
        [ -n "$SERIAL" ] || SERIAL="$(echo "$KEY" | sed -n 's|.*\ \([0-9A-Z]\+\)$|\1|p')"
        MAC="$(echo "$KEY" | sed -n 's|.*\ [0-9A-Z]\+@\([0-9a-z:]\+\)$|\1|p')"
        echo "Incoming '${SERIAL}' with '${MAC}'"
        mkdir -p incoming/$SERIAL
        echo "$KEY" > incoming/$SERIAL/ssh_key
        echo "$MAC" > incoming/$SERIAL/mac
    fi
}

MYSELF="$(readlink -f "$0")"

mkdir -p "$BASE_DIR"
mkdir -p "$BASE_DIR"/accepted
mkdir -p "$BASE_DIR"/incoming
mkdir -p "$BASE_DIR"/transfering
chown turris-netboot "${BASE_DIR}"/accepted
chown turris-netboot "${BASE_DIR}"/incoming
chown turris-netboot "${BASE_DIR}"/transfering

cd "$BASE_DIR" || die "Can't cd to $BASE_DIR"
if [ "x$2" = "x-j" ]; then
    JSON=1
fi
case $1 in
    list-incoming)

        json_init
        json_add_array "incoming"
        list "incoming"
        json_close_array
        [ -z "$JSON" ] || jshn -w
        ;;

    list-accepted)

        json_init
        json_add_array "accepted"
        list "accepted"
        json_close_array
        [ -z "$JSON" ] || jshn -w
        ;;

    list-transfering)

        json_init
        json_add_array "transfering"
        list "transfering"
        json_close_array
        [ -z "$JSON" ] || jshn -w
        ;;

    list-all|list)

        json_init
        json_add_array "accepted"
        list "accepted"
        json_close_array
        json_add_array "incoming"
        list "incoming"
        json_close_array
        json_add_array "transfering"
        list "transfering"
        json_close_array
        [ -z "$JSON" ] || jshn -w
        ;;

    accept) accept "$(ensure_hexa "$2")" ;;
    revoke) revoke "$(ensure_hexa "$2")" ;;
    register) register ;;
    regen) regen "$2" ;;
    get_rootfs) get_rootfs ;;
    update_rootfs)
        if [ "x$2" = "x-s" ]; then
            # Sleep up to 2 hours
            sleep "$(expr $(printf '%d' 0x$(head -c 2 /dev/urandom | hexdump -e '"%02x"')) % 7200)"
        fi
        update_rootfs
        ;;
    *) cat << EOF
Available commands:

    list-incoming       List routers waiting to be registered
    list-accepted       List registered routers
    list-transfering    List routers which are to be moved from incoming to accepted
    list-all|list       List both types of routers

    accept <serial>     Accept routers request for registration
    revoke <serial>     Revoke routers access
    regen               Regenerate configuration
    get_rootfs          Download rootfs that is being served
    update_rootfs [-s]  Check whether there is a newer rootfs to serve
                        Use -s to add random delay up to two hours

Use -j as a first argument to get lists in json format
EOF
esac
