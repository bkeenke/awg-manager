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
 -s <server> : Server host for user connection
 -I : Interface (default auto)
 -h : Usage
 ```

## Quick start

Run server (bare-metal or VPS) with Ubuntu 20.02, 22.02

```
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/bkeenke/awg-manager/master/init.sh)" @ install
```
Or

## Build AmneziaWG and Install additional packages

```bash
apt update && apt upgrade -y
apt install build-essential curl make git wget qrencode python3 python3-pip -y

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


