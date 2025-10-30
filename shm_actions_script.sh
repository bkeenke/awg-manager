#!/bin/bash

set -e

EVENT="{{ event_name }}"
AWG_MANAGER="/etc/amnezia/amneziawg/awg-manager.sh"
CONF_DIR="/etc/amnezia/amneziawg"
SESSION_ID="{{ user.gen_session.id }}"
API_URL="{{ config.api.url }}"

echo "EVENT=$EVENT"

case $EVENT in
    INIT)
        echo
        echo "Init"
apt update
apt install -y build-essential \
    sudo \
    curl \
    make \
    git \
    wget \
    qrencode \
    python3 \
    python3-pip \
    iptables \
    libmnl-dev \
    libssl-dev \
    gcc \
    libffi-dev \
    libgmp-dev

        bash -c "$(curl -sL https://raw.githubusercontent.com/bkeenke/awg-manager/master/init.sh)" @ install >> /dev/null
        echo
        SERVER_HOST="{{ server.settings.host_name }}"
        if [ -z $SERVER_HOST ]; then
            SERVER_HOST=`ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | grep -v "inet6" | head -n 1 | awk '/inet/ {print $2}' | awk -F/ '{print $1}'`
        fi
        echo "Check domain: $API_URL"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $API_URL/shm/v1/test)
        if [ $HTTP_CODE -ne '200' ]; then
            echo "ERROR: incorrect API URL: $API_URL"
            echo "Got status: $HTTP_CODE"
            exit 1
        fi
        echo
        mkdir -p $CONF_DIR

        echo "Init server"
        chmod 700 $AWG_MANAGER
        $AWG_MANAGER -i -s $SERVER_HOST
         reboot
        ;;
    CREATE)
        echo "Create new user"
        USER_CFG=$($AWG_MANAGER -u "vpn-{{ us.id }}" -c -p)
        echo "Upload user key to SHM"
        curl -s -XPUT \
            -H "session-id: $SESSION_ID" \
            -H "Content-Type: text/plain" \
            $API_URL/shm/v1/storage/manage/vpn_awg{{ us.id }} \
            --data-binary "$USER_CFG"
        echo
        RAW_USER_CFG=$($AWG_MANAGER -u "vpn-{{ us.id }}" -pr)
        curl -s -XPUT \
            -H "session-id: $SESSION_ID" \
            -H "Content-Type: text/plain" \
            $API_URL/shm/v1/storage/manage/vpn_awg_raw{{ us.id }} \
            --data-binary "$USER_CFG"
        echo "done"
        ;;
    ACTIVATE)
        echo "Activate user"
        $AWG_MANAGER -u "vpn-{{ us.id }}" -U
        echo "done"
        ;;
    BLOCK)
        echo "Block user"
        $AWG_MANAGER -u "vpn-{{ us.id }}" -L
        echo "done"
        ;;
    REMOVE)
        echo "Remove user"
        $AWG_MANAGER -u "vpn-{{ us.id }}" -d
        echo "Remove user key from SHM"
        curl -s -XDELETE \
            -H "session-id: $SESSION_ID" \
            $API_URL/shm/v1/storage/manage/vpn_awg{{ us.id }}
        curl -s -XDELETE \
            -H "session-id: $SESSION_ID" \
            $API_URL/shm/v1/storage/manage/vpn_awg_raw{{ us.id }}
        echo "done"
        ;;
    *)
        echo "Unknown event: $EVENT. Exit."
        exit 0
        ;;
esac
