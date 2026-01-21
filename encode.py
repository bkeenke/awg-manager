from os import system, name
from typing import TypedDict
import json
import sys
from PyQt6.QtCore import *


def pack(s):
    try:
        json.loads(s)
    except Exception as e:
        return 'ERROR: ' + str(e)
    ba = qCompress(QByteArray(s.encode()))
    ba = ba.toBase64(QByteArray.Base64Option.Base64UrlEncoding | QByteArray.Base64Option.OmitTrailingEquals)
    return str(ba, 'utf-8')

class WireguardConfInterfaceData(TypedDict):
    """
    the interface parameters from wireguard .conf file
    """
    PrivateKey: str
    Address: str
    DNS: str


class WireguardConfAdditionalInterfaceData(WireguardConfInterfaceData):
    """
    additional parameters used by the amnezia-wg protocol
    """
    Jc: int
    Jmin: int
    Jmax: int
    S1: int
    S2: int
    H1: int
    H2: int
    H3: int
    H4: int
    I1: str
    I2: str
    I3: str
    I4: str
    I5: str


class WireguardConfPeerData(TypedDict):
    """
    the peer parameters from wireguard .conf file
    """
    PublicKey: str
    PresharedKey: str
    AllowedIPs: str
    Endpoint: str
    Port: str


class WireguardConfFullData(TypedDict):
    Interface: WireguardConfInterfaceData
    Peer: WireguardConfPeerData


class WireguardConfParser:
    """
    .conf file parser
    """
    def __init__(self, conf_file: str):
        self.CONF_FILE = conf_file

    def read_data(self) -> str:
        """return a string with all the data from .conf file"""
        with open(self.CONF_FILE, 'r') as file:
            lines = file.readlines()
        return "".join(lines)

    def pack_config_data(self) -> WireguardConfFullData:
        """return packed data from .conf file

        packed date is an instance of WireguardConfFullData
        """
        wireguard_data: WireguardConfFullData = {}
        interface_data: WireguardConfInterfaceData = {}
        peer_data: WireguardConfPeerData = {}
        data = self.read_data()
        parsing_mode = ""

        for line in data.split('\n'):
            if line == '[Interface]':
                parsing_mode = 'interface'
                continue
            elif line == '[Peer]':
                parsing_mode = 'peer'
                continue

            line_list = [l.strip() for l in line.split('=', 1)]
            if line_list == ['']:
                continue

            if parsing_mode == 'interface':
                interface_data[line_list[0]] = line_list[1]
            if parsing_mode == 'peer':
                peer_data[line_list[0]] = line_list[1]

        wireguard_data['Interface'] = interface_data
        wireguard_data['Peer'] = peer_data

        return wireguard_data


def unpack_config_data(packed_config_data: WireguardConfFullData) -> str:
    """return string with the unpacked data from WireguardConfFullData instance"""
    data = ['[Interface]']

    for interface_key in packed_config_data['Interface']:
        value = packed_config_data['Interface'][interface_key]

        if interface_key == 'Address':
            value = value.split(',')[0]
        if interface_key == 'DNS':
            value = value.split(',')[0]

        data.append(f"{interface_key} = {value}")

    data.append('\n[Peer]')
    for peer_key in packed_config_data['Peer']:
        value = packed_config_data['Peer'][peer_key]
        data.append(f"{peer_key} = {value}")

    return "\n".join(data)


def add_parameters_in_config_data(packed_config_data: WireguardConfFullData):
    """updates packed data which is th instance of WireguardConfFullData

    more specifically data is the instance of WireguardConfAdditionalInterfaceData
    """
    additional_parameters: WireguardConfAdditionalInterfaceData = {
        'Jc': '7',
        'Jmin': '50',
        'Jmax': '1000',
        'S1': '116',
        'S2': '61',
        'H1': '1139437039',
        'H2': '1088834137',
        'H3': '977318325',
        'H4': '1583407056',
        'I1': '<b 0x4849>',
        'I2': '<r 32>',
        'I3': '<t>',
        'I4': '<rd 8><rc 4>',
        'I5': '<c>'
    }

    packed_config_data['Interface'].update(additional_parameters)


class AmneziaWgBuilder:
    """
    this class helps to encode (build) data from WireguardConfFullData instance
    """
    def __init__(self, wireguard_config_data: WireguardConfFullData, description: str):
        self.WIREGUARD_CONFIG_DATA = wireguard_config_data
        self.DESCRIPTION = description

    def build(self):
        """this method encodes information"""
        json_data = self.generate_json()
        print(pack(json_data))

    def get_string_wireguard_config_data(self):
        add_parameters_in_config_data(self.WIREGUARD_CONFIG_DATA.copy())
        return unpack_config_data(self.WIREGUARD_CONFIG_DATA).replace('\n', '\\n')

    def get_client_ip(self) -> str:
        return self.WIREGUARD_CONFIG_DATA["Interface"]["Address"].split(",")[0].split('/')[0]

    def generate_json(self) -> str:
        client_ip = self.get_client_ip()
        client_priv_key = self.WIREGUARD_CONFIG_DATA['Interface']['PrivateKey']
        config = self.get_string_wireguard_config_data()
        hostName, port = self.WIREGUARD_CONFIG_DATA['Peer']['Endpoint'].split(':')
        psk_key = self.WIREGUARD_CONFIG_DATA['Peer']["PresharedKey"]
        server_pub_key = self.WIREGUARD_CONFIG_DATA['Peer']['PublicKey']
        PRIMARY_DNS, SECONDARY_DNS = '1.1.1.1', '1.0.0.1'
        last_config = (
            '{\n'
            '    "H1": "1139437039",\n'
            '    "H2": "1088834137",\n'
            '    "H3": "977318325",\n'
            '    "H4": "1583407056",\n'
            '    "I1": "<b 0x4849>",\n'
            '    "I2": "<r 32>",\n'
            '    "I3": "<t>",\n'
            '    "I4": "<rd 8><rc 4>",\n'
            '    "I5": "<c>",\n'
            '    "Jc": "7",\n'
            '    "Jmax": "1000",\n'
            '    "Jmin": "50",\n'
            '    "S1": "116",\n'
            '    "S2": "61",\n'
            f'    "client_ip": "{client_ip}",\n'
            f'    "client_priv_key": "{client_priv_key}",\n'
            f'    "client_pub_key": "0",\n'
            f'    "config": "{config}",\n'
            f'    "hostName": "{hostName}",\n'
            f'    "port": {port},\n'
            f'    "psk_key": "{psk_key}",\n'
            f'    "server_pub_key": "{server_pub_key}"\n'
            '}\n'
        )

        json_value = {
            "containers": [
                {
                    "awg": {
                        "H1": "1139437039",
                        "H2": "1088834137",
                        "H3": "977318325",
                        "H4": "1583407056",
                        "I1": "<b 0x4849>",
                        "I2": "<r 32>",
                        "I3": "<t>",
                        "I4": "<rd 8><rc 4>",
                        "I5": "<c>",
                        "Jc": "7",
                        "Jmax": "1000",
                        "Jmin": "50",
                        "S1": "116",
                        "S2": "61",
                        "last_config": f'{last_config}',
                        "port": f"{port}",
                        "transport_proto": "udp"
                    },
                    "container": "amnezia-awg"
                }
            ],
            "defaultContainer": "amnezia-awg",
            "description": f"{self.DESCRIPTION}",
            "dns1": f"{PRIMARY_DNS}",
            "dns2": f"{SECONDARY_DNS}",
            "hostName": f"{hostName}"
        }
        return json.dumps(json_value)

id = sys.argv[1]
usid= f'ShmBot_{id}'
def encode_config(path):

    file = WireguardConfParser(path)
    file = file.pack_config_data()

    awg = AmneziaWgBuilder(file, usid)
    jssn_ = awg.generate_json()
    vpn_ = pack(jssn_)
    return vpn_

if len(sys.argv) != 2:
    print("Usage: python encode.py us.id")
    sys.exit(1)

conf_file = f'/etc/amnezia/amneziawg/keys/{id}/{id}.conf'
vpn_ = encode_config(conf_file)
print (vpn_)
