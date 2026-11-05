# awg-manager

AmneziaWG manager allow initialize AmneziaWG server and manage users.

You can start the AmneziaWG server with one command, and then create (and delete) users.


```bash
Usage: ./awg-manager.sh [<options>] [command [arg]]
Options:
 -i : Init (Create server keys and configs)
 -c : Create new user
 -d : Delete user
 -L : Lock user
 -U : Unlock user
 -p : Print user config
 -q : Print user QR code
 -u <user> : User identifier (uniq field for vpn account)
 -s <server> : Server host for user connection (overrides SERVER_HOST from .env)
 -I <interface> : Interface (overrides SERVER_INTERFACE from .env, default auto)
 -h, --help : Usage
```

The script must be run as root. It works in `HOME_DIR` (`/etc/amnezia/amneziawg` by default),
so server configs and the `keys/` directory are always created there regardless of the current directory.

## Configuration (.env)

Settings are read from `.env` located next to `awg-manager.sh` (`.env` is not tracked by git).
Copy the template and edit it:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|---|---|---|
| `HOME_DIR` | `/etc/amnezia/amneziawg` | Directory with server configs and `keys/` |
| `SERVER_NAME` | `awg0` | Interface / server config name (`<SERVER_NAME>.conf`) |
| `SERVER_IP_PREFIX` | `10.10.90` | First three octets of the VPN subnet (server gets `.1`) |
| `SERVER_IP6_PREFIX` | — | IPv6 prefix ending with `::`, e.g. `fd10:10:90::` (server gets `::1`); empty = IPv4 only |
| `SERVER_PORT` | `43748` | UDP listen port |
| `SERVER_INTERFACE` | auto (default route) | External interface for NAT; `-I` overrides it |
| `SERVER_HOST` | — | Host/IP clients connect to; `-s` overrides it |
| `SERVER_MODE` | `internet` | `internet`: clients go out through the server; `local`: clients only reach each other (see [Firewall](#firewall)) |
| `CLIENT_DNS` | `8.8.8.8, 8.8.4.4` (+ Google IPv6 DNS with IPv6); empty in `local` mode | `DNS` of new user configs; set it empty (`CLIENT_DNS=`) to omit the line |
| `CLIENT_ALLOWED_IPS` | `0.0.0.0/0` (+ `::/0` with IPv6); in `local` mode the VPN subnet: `<SERVER_IP_PREFIX>.0/24` (+ `<SERVER_IP6_PREFIX>/120`) | `AllowedIPs` of new user configs |

All variables are optional: missing ones fall back to the defaults above.
Variables set in the environment take precedence over `.env` (see below).

### Server host

The `Endpoint` host for a new user is taken from (first found):
`-s` option → `SERVER_HOST` in `.env` → `keys/<server>/.server` (saved on init) → IP of `SERVER_INTERFACE`.

If a host is passed via `-s` (or set in `.env`) together with `-c` or `-p`, the `Endpoint` of an existing user config is updated,
and with `-p` the host is also saved to `keys/<server>/.server`.

### Several servers on one host

Each server is a separate `SERVER_NAME` with its own `SERVER_IP_PREFIX` and `SERVER_PORT`.
Switch between them by editing `.env` or by setting variables for a single run, e.g.:

```bash
SERVER_NAME=awg1 SERVER_IP_PREFIX=10.10.91 SERVER_PORT=43749 ./awg-manager.sh -i -s YOUR_SERVER_IP
SERVER_NAME=awg1 SERVER_IP_PREFIX=10.10.91 ./awg-manager.sh -c -u my_user
```

Variables passed this way override the values from `.env`. With `sudo` put them after `sudo`
(`sudo SERVER_NAME=awg1 SERVER_IP_PREFIX=10.10.91 ./awg-manager.sh ...`), because `sudo` resets the environment.

## Files layout

```
HOME_DIR/
  <server>.conf               # server config (awg0.conf, awg1.conf, ...)
  keys/<server>/
    .server                   # saved server host
    server/private.key        # server keys
    server/public.key
    <user>/<user>.conf        # client config
    <user>/{private,public,psk}.key
```

### Migration from the old layout

Older versions kept server keys in `keys/<server>/{private,public}.key` and users in `keys/<user>/`, `keys/.server`.
On any run the script detects the old layout for `SERVER_NAME` and moves it automatically:
server keys go to `keys/<server>/server/`, `keys/.server` is copied to `keys/<server>/.server`, and user directories
whose `Address` belongs to `SERVER_IP_PREFIX` are moved to `keys/<server>/<user>/`.

## Obfuscation parameters

On init (`-i`) AmneziaWG parameters `Jc`, `Jmin`, `Jmax`, `S1`–`S4`, `H1`–`H4`, `I1`–`I5` are generated randomly
and written to the server config. There is no separate params file: on user creation the parameters are copied
from `<server>.conf` into the client config. Parameters with empty values are skipped, because `awg` rejects them.

## Quick start

Run server (bare-metal or VPS) with Ubuntu 20.02, 22.02

```
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/bkeenke/awg-manager/master/init.sh)" @ install
```
Or

## Build AmneziaWG and Install additional packages

```bash
apt update && apt upgrade -y
apt install build-essential curl make git wget qrencode -y

#install Golang
mkdir -p /opt/go
cd /opt/go
wget https://go.dev/dl/go1.25.3.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.25.3.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin" >> /etc/profile
source /etc/profile
# if the go version does not show, then update the session

#Install amnezia-go
git clone https://github.com/amnezia-vpn/amneziawg-go.git /opt/amnezia-go
cd /opt/amnezia-go
make
#copy to amneziawg-go
cp /opt/amnezia-go/amneziawg-go /usr/bin/amneziawg-go

#Install amnezia-tools
git clone https://github.com/amnezia-vpn/amneziawg-tools.git /opt/amnezia-tools
cd /opt/amnezia-tools/src
make
make install

```

## Usage awg-manager
```
./awg-manager.sh -u Username -c
```

## User IP allocation

On `-c` each user gets the first free address `SERVER_IP_PREFIX.2` … `SERVER_IP_PREFIX.254` (`.1` is the server).
An address is considered taken if it is found in any of:

 - `Address` in user configs `keys/<server>/<user>/<user>.conf`
 - `Address` / `AllowedIPs` in the server config `<server>.conf` (including peers without a keys dir or edited manually)
 - allowed IPs of the running interface (`awg show <server> allowed-ips`)

Only single addresses (`/32` or without mask) from the `SERVER_IP_PREFIX` subnet are counted; routed subnets in `AllowedIPs` are ignored.
If you change a peer address by hand, keep the user config `Address` and the server `AllowedIPs` in sync.

### IPv6

With `SERVER_IP6_PREFIX` set each user also gets an IPv6 address with the same host number written in hex
(`10.10.90.10` → `fd10:10:90::a`), IPv6 DNS servers and `AllowedIPs = 0.0.0.0/0, ::/0`, so IPv6 traffic
goes through the tunnel instead of leaking past it. A ULA prefix (`fc…`/`fd…`) is NATed to the server's IPv6 address,
any other prefix is routed as is (no NAT66): it must be routed to the server by the provider (for Oracle Cloud: a route
rule for the prefix with the instance as the target and source/destination check skipped on its VNIC).
On init the script also enables `net.ipv6.conf.all.forwarding`.

To add IPv6 to an existing server: add `<prefix>1/128` to `Address` and the `ip6tables` `PostUp`/`PostDown` lines
(see below) to `<server>.conf`, then add an IPv6 address to `Address` of each user config and lock/unlock the user
(`-L`, `-U`) to rewrite the peer in the server config. Users have to re-import their configs.

## Firewall

On init `PostUp`/`PostDown` rules are written to the server config, so they exist only while the interface is up:

 - the UDP listen port is opened in `INPUT` (IPv4 and IPv6);
 - traffic from clients to `SERVER_INTERFACE` and replies back are allowed in `FORWARD` (images like Oracle Cloud Ubuntu end `FORWARD` with `REJECT`);
 - new connections from `SERVER_INTERFACE` to clients are dropped in `FORWARD` (matters for a public IPv6 prefix);
 - clients are NATed (`MASQUERADE`) on `SERVER_INTERFACE`.

The `FORWARD` rules are added for IPv6 too when `SERVER_IP6_PREFIX` is set, the IPv6 NAT rule only for a ULA prefix.
Traffic between clients is not allowed.

With `SERVER_MODE=local` there is no NAT and no way out: the only `FORWARD` rule allows traffic between clients
(`-i %i -o %i`), and user configs get no `DNS` and only the VPN subnet in `AllowedIPs`.

## Usage amneziawg-go

Simply run:
```
amneziawg-go awg0
```
This will create an interface and fork into the background. To remove the interface, use the usual ip link del wg0, or if your system does not support removing interfaces directly, you may instead remove the control socket via rm -f /var/run/amneziawg/wg0.sock, which will result in amneziawg-go shutting down.

To run amneziawg-go without forking to the background, pass -f or --foreground:
```
amneziawg-go -f awg0
```
When an interface is running, you may use amnezia-wg-tools `awg-quick`  to configure it, as well as the usual ip(8) and ifconfig(8) commands.

## Setup

 - Download this script [awg-manager.sh](https://raw.githubusercontent.com/bkeenke/awg-manager/master/awg-manager.sh) from GitHub
 - Initialize Annezia-WG server: `./awg-manager.sh -i -s YOUR_SERVER_IP`
 - Add your user: `./awg-manager.sh -c -u my_user -p > awg-client.conf`
 - Install AmneziaVPN on the client
 - Start client with config `awg-client.conf`


