#!/bin/sh
BASE_DIR="$HOME/clients"

[ "$(id -un)" = turris-netboot ] || exec su - turris-netboot "$0" "$@"

die() {
    echo "$@" >&2
    exit 1
}

list() {
    cd "$1"
    for i in */ssh_key; do
        [ -f "$i" ] || continue
        ID="$(dirname "$i")"
        echo " * $ID"
    done
    cd "$BASE_DIR"
}

get_rootfs() {
    mkdir -p "$HOME"/rootfs/
    cd "$HOME"/rootfs/
    if [ \! -f ./rootfs.tar.gz ]; then
        wget -O "$HOME"/rootfs/rootfs.tar.gz https://repo.turris.cz/hbs/medkit/mox-medkit-latest.tar.gz
        wget -O "$HOME"/rootfs/rootfs.tar.gz.sha256 https://repo.turris.cz/hbs/medkit/mox-medkit-latest.tar.gz.sha256
        sed -i 's|mox-medkit-*|rootfs.tar.gz|' "$HOME"/rootfs/rootfs.tar.gz.sha256
        sha256sum -c ./rootfs.tar.gz.sha256 || {
            rm -f ./rootfs.tar.gz*
            die "Download failed"
        }
    fi
    if [ ./rootfs.tar.gz -nt /srv/tftp/turris-netboot/mox ] || [ \! -f /srv/tftp/turris-netboot/mox ]; then
        cd "$HOME"/rootfs/
        rm -rf ./boot ./usr mox.its
        tar -xzf rootfs.tar.gz ./boot/Image ./boot/armada-3720-turris-mox.dtb ./usr/share/turris-netboot/initrd-aarch64 ./usr/share/turris-netboot/mox.itx || die "Wrong rootfs"
        rm -f mox.its
        cp ./usr/share/turris-netboot/mox.its .
        /usr/sbin/mkimage -f mox.its /srv/tftp/turris-netboot/mox || die "Can't create image"
        rm -rf ./boot ./usr mox.its
    fi
}

regen() {
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

accept() {
    [ -d "incoming/$1" ] || exit 1
    rm -rf "accepted/$1"
    mv "incoming/$1" "accepted/$1"
    head -c 16 /dev/urandom > accepted/$1/aes
    regen
}

revoke() {
    [ -d "accepted/$1" ] || exit 1
    rm -rf "accepted/$1"
    regen
}

register() {
    KEY="$(head -c 256 | grep '^ssh-ed25519 [a-zA-Z0-9/+=]\+ [0-9A-F]\+$')"
    if [ "$KEY" ]; then
        SERIAL="$(echo "$KEY" | sed 's|.*\ \([0-9A-Z]\+\)$|\1|')"
        mkdir -p incoming/$SERIAL
        echo "$KEY" > incoming/$SERIAL/ssh_key
    fi
}

MYSELF="$(readlink -f "$0")"

mkdir -p "$BASE_DIR"
mkdir -p "$BASE_DIR"/accepted
mkdir -p "$BASE_DIR"/incoming
cd "$BASE_DIR"
case $1 in
    list-incoming) list "incoming" ;;
    list-accepted) list "accepted" ;;
    list-all)
        echo "Accepted:"
        list "accepted"
        echo
        echo Incoming:
        list "incoming"
        ;;
    accept) accept "$2" ;;
    revoke) revoke "$2" ;;
    register) register ;;
    regen) regen ;;
    get_rootfs) get_rootfs ;;
    *) cat << EOF
Available commands:

    list-incoming     List routers waiting to be registered
    list-accepted     List registered routers
    list-all          List both types of routers

    accept [serial]   Accept routers request for registration
    revoke [serial]   Revoke routers access
    regen             Regenerate configuration
    get_rootfs        Update rootfs that is being served

EOF
esac
