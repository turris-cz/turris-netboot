#!/usr/bin/env python3

import errno
import fcntl
import ipaddress
import sys
import subprocess
import time

from euci import EUci


def err(text):
    sys.stderr.write(f"{text}\n")
    sys.stderr.flush()
    exit(1)


# Make sure that following code is not run by other process at the same time
lockfile = open("/tmp/.netboot-static-lease-script", "w")
while True:
    try:
        fcntl.flock(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except IOError as e:
        if e.errno != errno.EAGAIN:
            err("Failed to obtain the lock.")
            raise
        else:
            time.sleep(0.2)

# parse cmd line
if len(sys.argv) != 3:
    err(f"usage: {sys.argv[0]} DEVICE_ID MAC_ADDR")

_, device_id, device_mac = sys.argv

# read all host records
with EUci() as uci:
    # filter (pyuci can't filter by session type yet)
    records = [v for k, v in uci.get_all("dhcp").items() if "mac" in v and "ip" in v]

    lan_ip = uci.get("network", "lan", "ipaddr")
    lan_netmask = uci.get("network", "lan", "netmask")
    dhcp_start = uci.get_integer("dhcp", "lan", "start")
    dhcp_limit = uci.get_integer("dhcp", "lan", "limit")

# mac can contain multiple mac addresses => split and flatten
macs = [e.upper() for record in records for e in record["mac"].split(" ")]

if device_mac in macs:
    print(f"Device mac {device_mac} already present within static leases")
    sys.exit(0)

# Now lets try to find a new IP for our device
static_ips = [ipaddress.ip_address(e["ip"]) for e in records if e["ip"] != "ignore"]
router_ip = ipaddress.ip_address(lan_ip)
lan_network = ipaddress.ip_network(f"{lan_ip}/{lan_netmask}", strict=False)
dynamic_start = lan_network.network_address + dhcp_start
dynamic_last = dynamic_start + dhcp_limit

free_ip = None
iter_ip = dynamic_last + 1
# Try to get free ip after dynamic range
while iter_ip in lan_network:
    if iter_ip not in static_ips:
        free_ip = iter_ip
        break
    iter_ip += 1

if not free_ip:
    # Try to obtain ip before dynamic range
    iter_ip = dynamic_start - 1
    while iter_ip > lan_network.network_address:
        if iter_ip not in static_ips:
            free_ip = iter_ip
            break
        iter_ip -= 1

    if not free_ip:
        err(f"Can't find a free ip to assing.")
        sys.exit(1)

# set new record
with EUci() as uci:
    uci.set("dhcp", device_id, "host")
    uci.set("dhcp", device_id, "ip", str(free_ip))
    uci.set("dhcp", device_id, "mac", device_mac)
    uci.set("dhcp", device_id, "name", device_id)
    uci.commit("dhcp")

sub = subprocess.Popen(["/etc/init.d/dnsmasq", "restart"])
rc = sub.wait()
if rc != 0:
    err(f"New static IP was assigned {free_ip}, but failed to restart dnsmasq")

print(free_ip)
