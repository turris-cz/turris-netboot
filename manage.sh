#!/bin/sh
. /usr/share/libubox/jshn.sh

BASE_DIR="$(eval echo ~turris-netboot)/clients"

CMD="$0"
ARGUMENTS="$@"

set_netboot_user() {
    local args=${1:-$ARGUMENTS}
    [ "$(id -un)" = turris-netboot ] || exec su turris-netboot -- "$CMD" $args
}


JSON=""
THIS_ID=$(/usr/bin/crypto-wrapper serial-number 2> /dev/null || echo "netboot_master")

die() {
    echo "$@" >&2
    exit 1
}

list() {
    cd "$1"
    if [ -n "$JSON" ]; then
        echo "\"$1\": ["
    else
        echo "$1:" | sed -e 's|^a|A|' -e 's|^i|I|'
    fi
    DELIM=""
    for i in */ssh_key; do
        [ -f "$i" ] || continue
        ID="$(dirname "$i")"
        if [ -n "$JSON" ]; then
            echo "$DELIM \"$ID\""
            DELIM=","
        else
            echo " * $ID"
        fi
    done
    if [ -n "$JSON" ]; then
        echo "]"
    else
        echo
    fi
    cd "$BASE_DIR"
}

get_rootfs() {
    set_netboot_user

    mkdir -p "$HOME"/rootfs/
    cd "$HOME"/rootfs/
    if [ \! -f ./rootfs.tar.gz ] || [ "x$1" = "x-f" ]; then
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
    set_netboot_user

    wget -O /tmp/rootfs-check.tar.gz.sha256 https://repo.turris.cz/hbs/netboot/mox-netboot-latest.tar.gz.sha256
    sed -i 's|mox-netboot-.*|rootfs.tar.gz|' /tmp/rootfs-check.tar.gz.sha256
    cd "$HOME"/rootfs/
    sha256sum -c /tmp/rootfs-check.tar.gz.sha256 || {
        get_rootfs -f
    }
    rm -f /tmp/rootfs-check.tar.gz.sha256
}

regen() {
    set_netboot_user regen

    cd "$BASE_DIR"/accepted
    [ -f ~/.ssh/reg_key.pub ] || ssh-keygen -t ed25519 -f ~/.ssh/reg_key -N "" -C "registration_key"
    cat > /srv/tftp/pxelinux.cfg/default-arm-mvebu-turris_mox << EOF
default pair
prompt 0
timeout 0

label pair
    kernel /turris-netboot/mox
    append reg_key=$(grep '^[^-]' ~/.ssh/reg_key | tr '\n' ' ' | sed 's| ||g') pub_key=$(ssh-keyscan localhost 2> /dev/null | sed -n 's|localhost ssh-ed25519 ||p') console=ttyMV0,115200 earlycon=ar3700_uart,0xd0012000
EOF
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
    get_rootfs
    cd "$BASE_DIR"/accepted
    for i in */aes; do
        [ -f "$i" ] || continue
        if [ /srv/tftp/turris-netboot/mox_$(dirname "$i") -ot /srv/tftp/turris-netboot/mox ] || \
           [ \! -f /srv/tftp/turris-netboot/mox_$(dirname "$i") ]; then
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
    cp accepted/$1/remote/ca.crt "${target_dir}/ca.crt"
    cp accepted/$1/remote/02.crt "${target_dir}/token.crt"
    cp accepted/$1/remote/02.key "${target_dir}/token.key"

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

    rm -rf  "$target_dir" "$token_file" "$msg_file"
}

accept() {
    # this should be run as root
    [ -d "incoming/$1" ] || exit 1
    rm -rf "accepted/$1"
    mv "incoming/$1" "accepted/$1"
    head -c 16 /dev/urandom > accepted/$1/aes
    # generate remote access CA and certificates (should create accepted/../remove dir)
    generate_remote_access_certs "accepted/$1" "$1"
    # store static lease
    local mac="$(cat accepted/$1/mac)"
    local new_ip=$(netboot-set-static-lease ${1} ${mac} 2>/dev/null)
    echo "IP address $new_ip was allocated for ${1} (${mac})"
    prepare_client_token "$1" "$new_ip"
    chown -R turris-netboot:turris-netboot accepted/$1
    regen
}

revoke() {
    set_netboot_user

    [ -d "accepted/$1" ] || exit 1
    rm -rf "accepted/$1"
    regen
}

register() {
    set_netboot_user

    KEY="$(head -c 256 | grep '^ssh-ed25519 [a-zA-Z0-9/+=]\+ [0-9A-F]\+@[0-9a-f:]\+$')"
    if [ "$KEY" ]; then
        SERIAL="$(echo "$KEY" | sed 's|.*\ \([0-9A-Z]\+\)@[0-9a-z:]\+$|\1|')"
        MAC="$(echo "$KEY" | sed 's|.*\ [0-9A-Z]\+@\([0-9a-z:]\+\)$|\1|')"
        echo "Incomming '${SERIAL}' with '${MAC}'"
        mkdir -p incoming/$SERIAL
        echo "$KEY" > incoming/$SERIAL/ssh_key
        echo "$MAC" > incoming/$SERIAL/mac
    fi
}

MYSELF="$(readlink -f "$0")"

mkdir -p "$BASE_DIR"
mkdir -p "$BASE_DIR"/accepted
mkdir -p "$BASE_DIR"/incoming
cd "$BASE_DIR"
if [ "x$2" = "x-j" ]; then
    JSON=1
fi
case $1 in
    list-incoming)
        set_netboot_user
        [ -z "$JSON" ] || echo "{"
        list "incoming"
        [ -z "$JSON" ] || echo "}"
        ;;
    list-accepted)
        set_netboot_user
        [ -z "$JSON" ] || echo "{"
        list "accepted"
        [ -z "$JSON" ] || echo "}"
        ;;
    list-all)
        set_netboot_user
        [ -z "$JSON" ] || echo "{"
        list "accepted"
        [ -z "$JSON" ] || echo ","
        list "incoming"
        [ -z "$JSON" ] || echo "}"
        ;;
    accept) accept "$2" ;;
    revoke) revoke "$2" ;;
    register) register ;;
    regen) regen ;;
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
    list-all            List both types of routers

    accept <serial>     Accept routers request for registration
    revoke <serial>     Revoke routers access
    regen               Regenerate configuration
    get_rootfs          Download rootfs that is being served
    update_rootfs [-s]  Check whether there is a newer rootfs to serve
                        Use -s to add random delay up to two hours

Use -j as a first argument to get lists in json format
EOF
esac
