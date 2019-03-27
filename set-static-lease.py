#!/usr/bin/env python3

import ipaddress
import sys
import subprocess

from euci import EUci

# TODO implement some kind of locking


def err(text):
    sys.stderr.write(f"{text}\n")
    sys.stderr.flush()
    exit(1)


# parse cmd line
if len(sys.argv) != 3:
    err(f"usage: {sys.argv[0]} IP DEVICE_ID")

device_ip = ipaddress.ip_address(sys.argv[1])
device_id = sys.argv[2]

# fist obtain hw address from dhcp leases
device_mac = None
with open("/tmp/dhcp.leases") as f:
    for line in f.readlines():
        _, mac, ip, _, _ = line.strip().split(" ")
        if ipaddress.ip_address(ip) == device_ip:
            device_mac = mac.upper()
            break

if not device_mac:
    err(f"IP {device_ip} not in lease file")

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
    print(f"Device mac {device_mac} already present in static leases")
    sys.exit(0)

# Now lets try to find a new IP for our device
static_ips = [ipaddress.ip_address(e["ip"]) for e in records if e["ip"] != "ignore"]
router_ip = ipaddress.ip_address(lan_ip)
lan_network = ipaddress.ip_network(f"{lan_ip}/{lan_netmask}", strict=False)
dynamic_start = router_ip + dhcp_start
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
    while iter_ip > router_ip:
        if iter_ip not in static_ips:
            free_ip = iter_ip
            break
        iter_ip -= 1

    if not free_ip:
        err(f"Can't find a free ip to assing.")

# set new record
with EUci() as uci:
    uci.set("dhcp", device_id, "host")
    uci.set("dhcp", device_id, "ip", str(free_ip))
    uci.set("dhcp", device_id, "mac", mac)
    uci.set("dhcp", device_id, "name", device_id)
    uci.commit("dhcp")

sub = subprocess.Popen(["/etc/init.d/dnsmasq", "restart"])
rc = sub.wait()
if rc != 0:
    err(f"New static IP was assigned {free_ip}, but failed to restart dnsmasq")
