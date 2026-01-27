#!/bin/bash

set -e

colorized_echo() {
    local color=$1
    local text=$2

    case $color in
        "red")
        printf "\e[91m${text}\e[0m\n";;
        "green")
        printf "\e[92m${text}\e[0m\n";;
        "yellow")
        printf "\e[93m${text}\e[0m\n";;
        "blue")
        printf "\e[94m${text}\e[0m\n";;
        "magenta")
        printf "\e[95m${text}\e[0m\n";;
        "cyan")
        printf "\e[96m${text}\e[0m\n";;
        *)
            echo "${text}"
        ;;
    esac
}

installing() {
    check_running_as_root
    detect_os
    detect_and_update_package_manager
    install_package
    install_go
    install_awg_awg_tools
    install_awg_manager
}
check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "This command must be run as root."
        exit 1
    fi
}
detect_os() {
    # Detect the operating system
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
        elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
        elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
        elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}
detect_and_update_package_manager() {
    colorized_echo blue "Updating package manager"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        PKG_MANAGER="apt-get"
        $PKG_MANAGER update
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}
install_package () {
    if [ -z $PKG_MANAGER ]; then
        detect_and_update_package_manager
    fi
    colorized_echo blue "Installing Package"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        $PKG_MANAGER -y install build-essential \
        curl \
        make \
        git \
        wget \
        qrencode
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}

install_go() {
    if command -v go &> /dev/null; then
        colorized_echo green "Go already installed: $(go version)"
        return 0
    fi

    colorized_echo blue "Installing Go..."

    local GO_VERSION="1.25.3"
    local GO_ARCHIVE="go${GO_VERSION}.linux-amd64.tar.gz"
    local TEMP_DIR=$(mktemp -d)

    cd "$TEMP_DIR"
    wget -q "https://go.dev/dl/${GO_ARCHIVE}" || {
        colorized_echo red "Failed to download Go"
        rm -rf "$TEMP_DIR"
        exit 1
    }

    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$GO_ARCHIVE" || {
        colorized_echo red "Failed to extract Go"
        rm -rf "$TEMP_DIR"
        exit 1
    }

    # Cleanup temp directory
    rm -rf "$TEMP_DIR"

    # Add to PATH
    if ! grep -q '/usr/local/go/bin' /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi
    export PATH=$PATH:/usr/local/go/bin

    if command -v go &> /dev/null; then
        colorized_echo green "Go installed successfully: $(go version)"
    else
        colorized_echo red "Go installation failed"
        exit 1
    fi
}
install_awg_awg_tools() {
    # Check if awg and amneziawg-go are already installed
    if command -v awg &> /dev/null && command -v amneziawg-go &> /dev/null; then
        colorized_echo green "AmneziaWG already installed"
        return 0
    fi

    # Install amneziawg-go
    if ! command -v amneziawg-go &> /dev/null; then
        colorized_echo blue "Installing amneziawg-go..."

        rm -rf /opt/amnezia-go
        git clone https://github.com/amnezia-vpn/amneziawg-go.git /opt/amnezia-go || {
            colorized_echo red "Failed to clone amneziawg-go"
            exit 1
        }

        cd /opt/amnezia-go
        make || {
            colorized_echo red "Failed to build amneziawg-go"
            exit 1
        }

        cp /opt/amnezia-go/amneziawg-go /usr/bin/amneziawg-go
        chmod +x /usr/bin/amneziawg-go

        # Cleanup
        rm -rf /opt/amnezia-go

        if command -v amneziawg-go &> /dev/null; then
            colorized_echo green "amneziawg-go installed successfully"
        else
            colorized_echo red "amneziawg-go installation failed"
            exit 1
        fi
    else
        colorized_echo green "amneziawg-go already installed"
    fi

    # Install awg-tools
    if ! command -v awg &> /dev/null; then
        colorized_echo blue "Installing awg-tools..."

        rm -rf /opt/amnezia-tools
        git clone https://github.com/amnezia-vpn/amneziawg-tools.git /opt/amnezia-tools || {
            colorized_echo red "Failed to clone amneziawg-tools"
            exit 1
        }

        cd /opt/amnezia-tools/src
        make || {
            colorized_echo red "Failed to build awg-tools"
            exit 1
        }
        make install || {
            colorized_echo red "Failed to install awg-tools"
            exit 1
        }

        # Cleanup
        rm -rf /opt/amnezia-tools

        if command -v awg &> /dev/null; then
            colorized_echo green "awg-tools installed successfully"
        else
            colorized_echo red "awg-tools installation failed"
            exit 1
        fi
    else
        colorized_echo green "awg-tools already installed"
    fi
}
install_awg_manager() {
    local AWG_DIR="/etc/amnezia/amneziawg"
    local AWG_SCRIPT="${AWG_DIR}/awg-manager.sh"

    if [ -f "$AWG_SCRIPT" ]; then
        colorized_echo green "awg-manager.sh already installed"
        return 0
    fi

    colorized_echo blue "Installing awg-manager..."

    mkdir -p "$AWG_DIR" || {
        colorized_echo red "Failed to create directory ${AWG_DIR}"
        exit 1
    }

    wget -q -O "$AWG_SCRIPT" https://raw.githubusercontent.com/bkeenke/awg-manager/master/awg-manager.sh || {
        colorized_echo red "Failed to download awg-manager.sh"
        exit 1
    }

    chmod 700 "$AWG_SCRIPT"

    if [ -f "$AWG_SCRIPT" ]; then
        colorized_echo green "awg-manager.sh installed successfully"
    else
        colorized_echo red "awg-manager.sh installation failed"
        exit 1
    fi
}
case "$1" in
    install)
    shift; installing "$@";;
    *)
    usage;;
esac

