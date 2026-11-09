#!/bin/bash -e

APP=$(basename $0)
LOCKFILE="/tmp/$APP.lock"

trap "rm -f ${LOCKFILE}; exit" INT TERM EXIT
if ! ln -s $APP $LOCKFILE 2>/dev/null; then
    echo "ERROR: script LOCKED" >&2
    exit 15
fi

function usage {
  echo "Usage: $0 [<options>] [command [arg]]"
  echo "Options:"
  echo " -i : Init (Create server keys and configs)"
  echo " -c : Create new user"
  echo " -d : Delete user"
  echo " -L : Lock user"
  echo " -U : Unlock user"
  echo " -p : Print user config"
  echo " -q : Print user QR code"
  echo " -u <user> : User identifier (uniq field for vpn account)"
  echo " -s <server> : Server host for user connection (overrides SERVER_HOST from .env)"
  echo " -I <interface> : Interface (overrides SERVER_INTERFACE from .env, default auto)"
  echo " -h, --help : Usage"
  exit 1
}

unset USER
umask 0077

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "${SCRIPT_DIR}/.env" ]; then
    # Variables set in the environment take precedence over .env
    declare -A ENV_OVERRIDES
    for VAR in HOME_DIR SERVER_NAME SERVER_IP_PREFIX SERVER_IP6_PREFIX SERVER_PORT SERVER_INTERFACE SERVER_HOST SERVER_MODE CLIENT_DNS CLIENT_ALLOWED_IPS; do
        if [ -n "${!VAR+x}" ]; then
            ENV_OVERRIDES[$VAR]="${!VAR}"
        fi
    done
    source "${SCRIPT_DIR}/.env"
    for VAR in "${!ENV_OVERRIDES[@]}"; do
        printf -v "$VAR" '%s' "${ENV_OVERRIDES[$VAR]}"
    done
fi

HOME_DIR="${HOME_DIR:-/etc/amnezia/amneziawg}"
SERVER_NAME="${SERVER_NAME:-awg0}"
KEYS_DIR="keys/${SERVER_NAME}"
SERVER_IP_PREFIX="${SERVER_IP_PREFIX:-10.10.90}"
# IPv6 prefix ending with "::" (e.g. fd10:10:90::), empty = IPv4 only
SERVER_IP6_PREFIX="${SERVER_IP6_PREFIX}"
SERVER_PORT="${SERVER_PORT:-43748}"
SERVER_INTERFACE="${SERVER_INTERFACE:-$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)}"
SERVER_HOST="${SERVER_HOST}"
# internet: clients go out through the server; local: clients only reach each other
SERVER_MODE="${SERVER_MODE:-internet}"
if [ "$SERVER_MODE" != "internet" ] && [ "$SERVER_MODE" != "local" ]; then
    echo "ERROR: SERVER_MODE must be internet or local" >&2
    exit 1
fi
# Written to new user configs; set CLIENT_DNS empty to omit the DNS line
if [ "$SERVER_MODE" == "local" ]; then
    # User addresses are <prefix>2 … <prefix>fe, so /120 covers all of them
    CLIENT_DNS="${CLIENT_DNS-}"
    CLIENT_ALLOWED_IPS="${CLIENT_ALLOWED_IPS:-${SERVER_IP_PREFIX}.0/24${SERVER_IP6_PREFIX:+, ${SERVER_IP6_PREFIX}/120}}"
else
    CLIENT_DNS="${CLIENT_DNS-8.8.8.8, 8.8.4.4${SERVER_IP6_PREFIX:+, 2001:4860:4860::8888, 2001:4860:4860::8844}}"
    CLIENT_ALLOWED_IPS="${CLIENT_ALLOWED_IPS:-0.0.0.0/0${SERVER_IP6_PREFIX:+, ::/0}}"
fi

# Support --help, help, usage
for arg in "$@"; do
  if [ "$arg" == "--help" ] || [ "$arg" == "help" ] || [ "$arg" == "usage" ]; then
    usage
  fi
done

while getopts ":icdpqhLUu:I:s:h" opt; do
  case $opt in
     i) INIT=1 ;;
     c) CREATE=1 ;;
     d) DELETE=1 ;;
     L) LOCK=1 ;;
     U) UNLOCK=1 ;;
     p) PRINT_USER_CONFIG=1 ;;
     q) PRINT_QR_CODE=1 ;;
     u) USER="$OPTARG" ;;
     I) SERVER_INTERFACE="$OPTARG" ;;
     h) usage ;;
     s) SERVER_HOST="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" ; exit 1 ;;
     :) echo "Option -$OPTARG requires an argument" ; exit 1 ;;
  esac
done

[ $# -lt 1 ] && usage

function reload_server {
    awg syncconf ${SERVER_NAME} <(awg-quick strip ${SERVER_NAME})
}

function get_new_ip {
    declare -A IP_EXISTS
    local PREFIX_RE="${SERVER_IP_PREFIX//./\\.}"

    # Collect host octets of SERVER_IP_PREFIX addresses already in use:
    # user configs, peers in server config (incl. users without keys dir) and the running interface
    for IP in $( {
            grep -hiP '^\s*(Address|AllowedIPs)\s*=' "${KEYS_DIR}"/*/*.conf "$SERVER_NAME.conf" 2>/dev/null
            awg show "${SERVER_NAME}" allowed-ips 2>/dev/null
        } | grep -Po "(?<![\d.])${PREFIX_RE}\.\K\d+(?=(/32)?(\s|,|$))" || true )
    do
        IP_EXISTS[$IP]=1
    done

    for IP in {2..255}
    do
        [ ${IP_EXISTS[$IP]} ] || break
    done

    if [ $IP -eq 255 ]; then
        echo "ERROR: can't determine new address" >&2
        exit 3
    fi

    echo "${SERVER_IP_PREFIX}.${IP}/32"
}

# IPv6 address with the same host number as the IPv4 one (10.10.90.10 -> <prefix>a)
function ip6_for {
    printf '%s%x/128' "${SERVER_IP6_PREFIX}" "${1##*.}"
}

# Addresses from the Address line of a user config: IPv4 and IPv6 (if any), without masks
function user_ip4 {
    grep -iP '^\s*Address\s*=' "$1" | grep -Po '(?<![\d.])\d+\.\d+\.\d+\.\d+' | head -1
}

function user_ip6 {
    grep -iP '^\s*Address\s*=' "$1" | grep -Po '[0-9A-Fa-f]*:[0-9A-Fa-f:]+(?=/128)' | head -1
}

function add_user_to_server {
    if [ ! -f "${KEYS_DIR}/${USER}/public.key" ]; then
        echo "ERROR: User not exists" >&2
        exit 1
    fi

    local USER_PUB_KEY=$(cat "${KEYS_DIR}/${USER}/public.key")
    local USER_PSK_KEY=$(cat "${KEYS_DIR}/$USER/psk.key")
    local USER_IP=$(user_ip4 "${KEYS_DIR}/${USER}/${USER}.conf")
    local USER_IP6=$(user_ip6 "${KEYS_DIR}/${USER}/${USER}.conf")

    if grep "# BEGIN ${USER}$" "$SERVER_NAME.conf" >/dev/null ; then
        echo "User already exists"
        exit 0
    fi

cat <<EOF >> "$SERVER_NAME.conf"
# BEGIN ${USER}
[Peer]
PublicKey = ${USER_PUB_KEY}
AllowedIPs = ${USER_IP}${USER_IP6:+, ${USER_IP6}/128}
PresharedKey = ${USER_PSK_KEY}
# END ${USER}
EOF

    ip -4 route add ${USER_IP}/32 dev ${SERVER_NAME} || true
    [ -z "$USER_IP6" ] || ip -6 route add ${USER_IP6}/128 dev ${SERVER_NAME} || true
}

function remove_user_from_server {
    sed -i "/# BEGIN ${USER}$/,/# END ${USER}$/d" "$SERVER_NAME.conf"
    if [ -f "${KEYS_DIR}/${USER}/${USER}.conf" ]; then
        local USER_IP=$(user_ip4 "${KEYS_DIR}/${USER}/${USER}.conf")
        local USER_IP6=$(user_ip6 "${KEYS_DIR}/${USER}/${USER}.conf")
        ip -4 route del ${USER_IP}/32 dev ${SERVER_NAME} || true
        [ -z "$USER_IP6" ] || ip -6 route del ${USER_IP6}/128 dev ${SERVER_NAME} || true
    fi
}

# Legacy layout: keys/<server>/{private,public}.key, keys/<user>/, keys/.server
# New layout:    keys/<server>/server/{private,public}.key, keys/<server>/<user>/, keys/<server>/.server
function migrate_legacy_layout {
    if [ ! -f "${KEYS_DIR}/public.key" ] || [ -d "${KEYS_DIR}/server" ]; then
        return 0
    fi

    echo "Migrating legacy keys layout to ${KEYS_DIR}" >&2
    mkdir -p "${KEYS_DIR}/server"
    mv "${KEYS_DIR}/private.key" "${KEYS_DIR}/public.key" "${KEYS_DIR}/server/"

    if [ -f "keys/.server" ] && [ ! -f "${KEYS_DIR}/.server" ]; then
        cp "keys/.server" "${KEYS_DIR}/.server"
    fi

    # Users belong to this server if their address is in SERVER_IP_PREFIX subnet
    local CONF DIR NAME
    for CONF in keys/*/*.conf; do
        DIR=$(dirname "$CONF")
        NAME=$(basename "$DIR")
        [ "$CONF" == "${DIR}/${NAME}.conf" ] || continue
        grep -qiP "^Address\s*=\s*${SERVER_IP_PREFIX//./\\.}\.\d+(/|\s|$)" "$CONF" || continue
        echo "  ${NAME} -> ${KEYS_DIR}/${NAME}" >&2
        mv "$DIR" "${KEYS_DIR}/${NAME}"
    done
}

function init {
    local EFFECTIVE_SERVER_HOST="${SERVER_HOST}"
    if [ -z "$EFFECTIVE_SERVER_HOST" ]; then
        EFFECTIVE_SERVER_HOST=$(ip -4 addr show dev "$SERVER_INTERFACE" | grep -Po '(?<=inet )(\d+\.\d+\.\d+\.\d+)' | head -1)
    fi

    if [ -z "$EFFECTIVE_SERVER_HOST" ]; then
        echo "ERROR: Server host required (use -s or SERVER_HOST in .env)" >&2
        exit 1
    fi

    if [ -z "$SERVER_INTERFACE" ]; then
        echo "ERROR: Can't determine server interface" >&2
        echo "DEBUG: 'ip route':"
        ip route
        exit 1
    fi

    echo "Interface: $SERVER_INTERFACE"
    echo "Server Host: $EFFECTIVE_SERVER_HOST"

    mkdir -p "${KEYS_DIR}/server"
    echo -n "$EFFECTIVE_SERVER_HOST" > "${KEYS_DIR}/.server"

    if [ ! -f "${KEYS_DIR}/server/private.key" ]; then
        awg genkey | tee "${KEYS_DIR}/server/private.key" | awg pubkey > "${KEYS_DIR}/server/public.key"
    fi

    if [ -f "$SERVER_NAME.conf" ]; then
        echo "Server already initialized"
        exit 0
    fi

    SERVER_PVT_KEY=$(cat "${KEYS_DIR}/server/private.key")

    JC=$(( RANDOM % 11 ))
    JMIN=$(( 64 + RANDOM % 448 ))
    JMAX=$(( JMIN + RANDOM % (1025 - JMIN) ))
    S1=$(( RANDOM % 65 ))
    S2=$(( RANDOM % 65 ))
    while [ $((S1 + 56)) -eq $S2 ]; do S2=$(( RANDOM % 65 )); done
    S3=$(( RANDOM % 65 ))
    S4=$(( RANDOM % 33 ))
    H1=$(( 471800590 + RANDOM % 101 ))
    H2=$(( 1246894907 + RANDOM % 94 ))
    H3=$(( 923637689 + RANDOM % 2 ))
    H4=$(( 1769581055 + RANDOM % 100000001 ))
    I1=$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]'); I1="<b 0x${I1}>"
    I2=$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]'); I2="<b 0x${I2}>"
    I3=$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]'); I3="<b 0x${I3}>"
    I4=$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]'); I4="<b 0x${I4}>"
    I5=$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]'); I5="<b 0x${I5}>"

    # Open the listen port, let clients out (FORWARD may end with REJECT) and NAT them.
    # A public IPv6 prefix is routed without NAT; new connections from outside to clients are dropped.
    # In local mode clients are only allowed to reach each other.
    local IPT IPTABLES=iptables
    [ -z "$SERVER_IP6_PREFIX" ] || IPTABLES="iptables ip6tables"
    local FIREWALL=""
    for IPT in $IPTABLES; do
        if [ "$SERVER_MODE" == "local" ]; then
            FIREWALL+="PostUp = ${IPT} -I FORWARD 1 -i %i -o %i -j ACCEPT
PostDown = ${IPT} -D FORWARD -i %i -o %i -j ACCEPT
"
            continue
        fi
        if [ "$IPT" == "iptables" ] || [[ "${SERVER_IP6_PREFIX,,}" =~ ^f[cd] ]]; then
            FIREWALL+="PostUp = ${IPT} -t nat -A POSTROUTING -o ${SERVER_INTERFACE} -j MASQUERADE
PostDown = ${IPT} -t nat -D POSTROUTING -o ${SERVER_INTERFACE} -j MASQUERADE
"
        fi
        # Inserted at the top one by one, so they end up in reverse order: ACCEPT out, ACCEPT replies, DROP the rest
        FIREWALL+="PostUp = ${IPT} -I FORWARD 1 -i ${SERVER_INTERFACE} -o %i -j DROP
PostDown = ${IPT} -D FORWARD -i ${SERVER_INTERFACE} -o %i -j DROP
PostUp = ${IPT} -I FORWARD 1 -i ${SERVER_INTERFACE} -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostDown = ${IPT} -D FORWARD -i ${SERVER_INTERFACE} -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostUp = ${IPT} -I FORWARD 1 -i %i -o ${SERVER_INTERFACE} -j ACCEPT
PostDown = ${IPT} -D FORWARD -i %i -o ${SERVER_INTERFACE} -j ACCEPT
"
    done
    for IPT in iptables ip6tables; do
        FIREWALL+="PostUp = ${IPT} -I INPUT 1 -p udp -m udp --dport ${SERVER_PORT} -j ACCEPT
PostDown = ${IPT} -D INPUT -p udp -m udp --dport ${SERVER_PORT} -j ACCEPT
"
    done

cat <<EOF > "$SERVER_NAME.conf"
[Interface]
Address = ${SERVER_IP_PREFIX}.1/32${SERVER_IP6_PREFIX:+, ${SERVER_IP6_PREFIX}1/128}
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PVT_KEY}
${FIREWALL%$'\n'}
Jc = ${JC}
Jmin = ${JMIN}
Jmax = ${JMAX}
S1 = ${S1}
S2 = ${S2}
S3 = ${S3}
S4 = ${S4}
H1 = ${H1}
H2 = ${H2}
H3 = ${H3}
H4 = ${H4}
I1 = ${I1}
I2 = ${I2}
I3 = ${I3}
I4 = ${I4}
I5 = ${I5}

EOF

    echo net.ipv4.ip_forward=1 >> /etc/sysctl.conf
    if [ -n "$SERVER_IP6_PREFIX" ]; then
        echo net.ipv6.conf.all.forwarding=1 >> /etc/sysctl.conf
        # With forwarding on the kernel ignores router advertisements unless accept_ra=2
        if [ "$(sysctl -n net.ipv6.conf.${SERVER_INTERFACE}.accept_ra)" == "1" ]; then
            echo net.ipv6.conf.${SERVER_INTERFACE}.accept_ra=2 >> /etc/sysctl.conf
        fi
    fi
    sysctl -p

    systemctl enable awg-quick@${SERVER_NAME}
    awg-quick up ${SERVER_NAME} || true

    echo "Server initialized successfully"
    exit 0
}

function create {
    if [ -f "${KEYS_DIR}/${USER}/${USER}.conf" ]; then
        echo "WARNING: key ${USER}.conf already exists" >&2
        return 0
    fi

    local EFFECTIVE_SERVER_HOST="${SERVER_HOST}"
    if [ -z "$EFFECTIVE_SERVER_HOST" ]; then
        if [ -f "${KEYS_DIR}/.server" ]; then
            EFFECTIVE_SERVER_HOST=$(cat "${KEYS_DIR}/.server")
        else
            EFFECTIVE_SERVER_HOST=$(ip -4 addr show dev "$SERVER_INTERFACE" | grep -Po '(?<=inet )(\d+\.\d+\.\d+\.\d+)' | head -1)
        fi
    fi

    if [ -n "$SERVER_HOST" ] && [ -d "${KEYS_DIR}" ]; then
        echo -n "$SERVER_HOST" > "${KEYS_DIR}/.server"
    fi

    if [ -z "$EFFECTIVE_SERVER_HOST" ]; then
        echo "ERROR: Can't determine server host. Set SERVER_HOST in .env or use -s" >&2
        exit 1
    fi

    USER_IP=$( get_new_ip )
    local USER_IP6=""
    [ -z "$SERVER_IP6_PREFIX" ] || USER_IP6=$( ip6_for "${USER_IP%/*}" )

    mkdir -p "${KEYS_DIR}/${USER}"
    awg genkey | tee "${KEYS_DIR}/${USER}/private.key" | awg pubkey > "${KEYS_DIR}/${USER}/public.key"
    awg genpsk > "${KEYS_DIR}/${USER}/psk.key"

    USER_PVT_KEY=$(cat "${KEYS_DIR}/${USER}/private.key")
    USER_PUB_KEY=$(cat "${KEYS_DIR}/${USER}/public.key")
    USER_PSK_KEY=$(cat "${KEYS_DIR}/${USER}/psk.key")
    SERVER_PUB_KEY=$(cat "${KEYS_DIR}/server/public.key")

    # Copy only non-empty obfuscation params from server config (awg rejects empty values)
    local AWG_PARAMS=$(grep -iP "^(Jc|Jmin|Jmax|S[1-4]|H[1-4]|I[1-5])\s*=\s*\S" "$SERVER_NAME.conf")

cat <<EOF > "${KEYS_DIR}/${USER}/${USER}.conf"
[Interface]
PrivateKey = ${USER_PVT_KEY}
Address = ${USER_IP}${USER_IP6:+, ${USER_IP6}}${CLIENT_DNS:+
DNS = ${CLIENT_DNS}}
${AWG_PARAMS}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${EFFECTIVE_SERVER_HOST}:${SERVER_PORT}
AllowedIPs = ${CLIENT_ALLOWED_IPS}
PersistentKeepalive = 20
PresharedKey = ${USER_PSK_KEY}
EOF
    add_user_to_server
    reload_server
}

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root" >&2
    exit 1
fi

cd "$HOME_DIR"

migrate_legacy_layout

if [ $INIT ]; then
    init
    exit 0;
fi

if [ ! -f "${KEYS_DIR}/server/public.key" ]; then
    echo "ERROR: Run init script before" >&2
    exit 2
fi

if [ -z "${USER}" ]; then
    echo "ERROR: User required" >&2
    exit 1
fi

if [ $CREATE ]; then
    create
    # Update config if SERVER_HOST was provided even if user already exists
    if [ -n "$SERVER_HOST" ] && [ -f "${KEYS_DIR}/${USER}/${USER}.conf" ]; then
        sed -i "s|^Endpoint\s*=.*|Endpoint = ${SERVER_HOST}:${SERVER_PORT}|" "${KEYS_DIR}/${USER}/${USER}.conf"
    fi
fi

if [ $DELETE ]; then
    remove_user_from_server
    reload_server
    rm -rf "${KEYS_DIR}/${USER}"
    exit 0
fi

if [ $LOCK ]; then
    remove_user_from_server
    reload_server
    exit 0
fi

if [ $UNLOCK ]; then
    add_user_to_server
    reload_server
    exit 0
fi

if [ $PRINT_USER_CONFIG ]; then
    if [ -n "$SERVER_HOST" ] && [ -f "${KEYS_DIR}/${USER}/${USER}.conf" ]; then
        sed -i "s|^Endpoint\s*=.*|Endpoint = ${SERVER_HOST}:${SERVER_PORT}|" "${KEYS_DIR}/${USER}/${USER}.conf"
        # Also update keys/.server to persist this change
        echo -n "$SERVER_HOST" > "${KEYS_DIR}/.server"
    fi
    cat "${KEYS_DIR}/${USER}/${USER}.conf"
elif [ $PRINT_QR_CODE ]; then
    qrencode -t ansiutf8 < "${KEYS_DIR}/${USER}/${USER}.conf"
fi


exit 0
