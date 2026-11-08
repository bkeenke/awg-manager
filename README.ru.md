# awg-manager

[English](README.md) | **Русский**

AmneziaWG manager позволяет инициализировать сервер AmneziaWG и управлять пользователями.

Сервер AmneziaWG запускается одной командой, после чего можно создавать (и удалять) пользователей.


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

| Опция | Описание |
|---|---|
| `-i` | Инициализация (создать ключи и конфиги сервера) |
| `-c` | Создать пользователя |
| `-d` | Удалить пользователя |
| `-L` | Заблокировать пользователя |
| `-U` | Разблокировать пользователя |
| `-p` | Вывести конфиг пользователя |
| `-q` | Вывести QR-код пользователя |
| `-u <user>` | Идентификатор пользователя (уникальное поле VPN-аккаунта) |
| `-s <server>` | Хост сервера для подключения пользователей (переопределяет `SERVER_HOST` из `.env`) |
| `-I <interface>` | Интерфейс (переопределяет `SERVER_INTERFACE` из `.env`, по умолчанию определяется автоматически) |
| `-h`, `--help` | Справка |

Скрипт нужно запускать от root. Он работает в `HOME_DIR` (по умолчанию `/etc/amnezia/amneziawg`),
поэтому конфиги сервера и каталог `keys/` всегда создаются там, независимо от текущего каталога.

## Настройка (.env)

Настройки читаются из файла `.env`, лежащего рядом с `awg-manager.sh` (`.env` не отслеживается git).
Скопируйте шаблон и отредактируйте его:

```bash
cp .env.example .env
```

| Переменная | По умолчанию | Описание |
|---|---|---|
| `HOME_DIR` | `/etc/amnezia/amneziawg` | Каталог с конфигами сервера и `keys/` |
| `SERVER_NAME` | `awg0` | Имя интерфейса / конфига сервера (`<SERVER_NAME>.conf`) |
| `SERVER_IP_PREFIX` | `10.10.90` | Первые три октета VPN-подсети (сервер получает `.1`) |
| `SERVER_IP6_PREFIX` | — | IPv6-префикс, заканчивающийся на `::`, например `fd10:10:90::` (сервер получает `::1`); пусто = только IPv4 |
| `SERVER_PORT` | `43748` | UDP-порт для входящих подключений |
| `SERVER_INTERFACE` | авто (маршрут по умолчанию) | Внешний интерфейс для NAT; переопределяется `-I` |
| `SERVER_HOST` | — | Хост/IP, к которому подключаются клиенты; переопределяется `-s` |
| `SERVER_MODE` | `internet` | `internet`: клиенты выходят в интернет через сервер; `local`: клиенты видят только друг друга (см. [Файрвол](#файрвол)) |
| `CLIENT_DNS` | `8.8.8.8, 8.8.4.4` (+ IPv6 DNS Google при включённом IPv6); пусто в режиме `local` | `DNS` в конфигах новых пользователей; задайте пустое значение (`CLIENT_DNS=`), чтобы не добавлять строку |
| `CLIENT_ALLOWED_IPS` | `0.0.0.0/0` (+ `::/0` при IPv6); в режиме `local` — VPN-подсеть: `<SERVER_IP_PREFIX>.0/24` (+ `<SERVER_IP6_PREFIX>/120`) | `AllowedIPs` в конфигах новых пользователей |

Все переменные необязательны: для отсутствующих используются значения по умолчанию из таблицы.
Переменные, заданные в окружении, имеют приоритет над `.env` (см. ниже).

### Хост сервера

Хост `Endpoint` для нового пользователя берётся из первого найденного источника:
опция `-s` → `SERVER_HOST` в `.env` → `keys/<server>/.server` (сохраняется при инициализации) → IP интерфейса `SERVER_INTERFACE`.

Если хост передан через `-s` (или задан в `.env`) вместе с `-c` или `-p`, `Endpoint` в конфиге существующего пользователя обновляется,
а с `-p` хост также сохраняется в `keys/<server>/.server`.

### Несколько серверов на одном хосте

Каждый сервер — это отдельный `SERVER_NAME` со своими `SERVER_IP_PREFIX` и `SERVER_PORT`.
Переключаться между ними можно, редактируя `.env` или задавая переменные на один запуск, например:

```bash
SERVER_NAME=awg1 SERVER_IP_PREFIX=10.10.91 SERVER_PORT=43749 ./awg-manager.sh -i -s YOUR_SERVER_IP
SERVER_NAME=awg1 SERVER_IP_PREFIX=10.10.91 ./awg-manager.sh -c -u my_user
```

Переданные так переменные переопределяют значения из `.env`. С `sudo` указывайте их после `sudo`
(`sudo SERVER_NAME=awg1 SERVER_IP_PREFIX=10.10.91 ./awg-manager.sh ...`), потому что `sudo` сбрасывает окружение.

Другой вариант — отдельный клон репозитория для каждого сервера, каждый со своим `.env`
(например, `/root/awg-manager` для `awg0` и `/root/awg-manager-awg1` для `awg1`).

### Примеры

VPN в интернет с публичными IPv6-адресами для клиентов:

```bash
SERVER_NAME="awg1"
SERVER_IP_PREFIX="10.10.97"
SERVER_IP6_PREFIX="2001:db8:0:1:97::"
SERVER_PORT=43749
SERVER_INTERFACE=ens3
SERVER_HOST=vpn.example.com
```

То же с приватными IPv6-адресами (NAT66): `SERVER_IP6_PREFIX="fd10:10:97::"`. Без `SERVER_IP6_PREFIX` клиенты получают только IPv4.

VPN только между клиентами (без интернета через сервер, без DNS):

```bash
SERVER_NAME="awg0"
SERVER_IP_PREFIX="10.10.96"
SERVER_PORT=43748
SERVER_MODE=local
SERVER_HOST=vpn.example.com
```

Клиенты такого сервера получают `AllowedIPs = 10.10.96.0/24` и сохраняют собственное подключение к интернету и DNS.

### Настройки применяются только к новым конфигам

Значения `SERVER_*` записываются в `<server>.conf` при инициализации (`-i`), значения `CLIENT_*` — в конфиг пользователя при его создании (`-c`).
Инициализация ничего не делает, если `<server>.conf` уже существует, а существующие конфиги пользователей никогда не перезаписываются.
После изменения `.env` для работающего сервера отредактируйте конфиги вручную:

 - сервер: `Address` и `PostUp`/`PostDown` в `<server>.conf`; проще всего инициализировать тестовый сервер
   с тем же `.env` (например, `SERVER_NAME=awgtest`) и скопировать строки из его конфига;
   затем `systemctl restart awg-quick@<server>`;
 - пользователи: `Address`, `DNS`, `AllowedIPs` в `keys/<server>/<user>/<user>.conf`, затем заблокируйте и разблокируйте каждого пользователя (`-L`, `-U`),
   чтобы перезаписать его пир в конфиге сервера. Пользователям нужно заново импортировать конфиги (`-p` или `-q`).

## Структура файлов

```
HOME_DIR/
  <server>.conf               # конфиг сервера (awg0.conf, awg1.conf, ...)
  keys/<server>/
    .server                   # сохранённый хост сервера
    server/private.key        # ключи сервера
    server/public.key
    <user>/<user>.conf        # конфиг клиента
    <user>/{private,public,psk}.key
```

### Миграция со старой структуры

Старые версии хранили ключи сервера в `keys/<server>/{private,public}.key`, а пользователей — в `keys/<user>/` и `keys/.server`.
При любом запуске скрипт обнаруживает старую структуру для `SERVER_NAME` и автоматически переносит её:
ключи сервера перемещаются в `keys/<server>/server/`, `keys/.server` копируется в `keys/<server>/.server`, а каталоги пользователей,
чей `Address` принадлежит `SERVER_IP_PREFIX`, перемещаются в `keys/<server>/<user>/`.

## Параметры обфускации

При инициализации (`-i`) параметры AmneziaWG `Jc`, `Jmin`, `Jmax`, `S1`–`S4`, `H1`–`H4`, `I1`–`I5` генерируются случайно
и записываются в конфиг сервера. Отдельного файла с параметрами нет: при создании пользователя параметры копируются
из `<server>.conf` в конфиг клиента. Параметры с пустыми значениями пропускаются, потому что `awg` их не принимает.

## Быстрый старт

Запустите сервер (bare-metal или VPS) с Ubuntu 20.04, 22.04 или 24.04.
Ubuntu 26.04 (ядро 7.0) тоже работает после [исправления amneziawg-dkms](#amneziawg-dkms-не-собирается-на-ядре-70).

```
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/bkeenke/awg-manager/master/init.sh)" @ install
```
Или

## Сборка AmneziaWG и установка дополнительных пакетов

```bash
apt update && apt upgrade -y
apt install build-essential curl make git wget qrencode -y

# установка Golang
mkdir -p /opt/go
cd /opt/go
wget https://go.dev/dl/go1.25.3.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.25.3.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin" >> /etc/profile
source /etc/profile
# если версия go не отображается, перезапустите сессию

# установка amnezia-go
git clone https://github.com/amnezia-vpn/amneziawg-go.git /opt/amnezia-go
cd /opt/amnezia-go
make
# копирование amneziawg-go
cp /opt/amnezia-go/amneziawg-go /usr/bin/amneziawg-go

# установка amnezia-tools
git clone https://github.com/amnezia-vpn/amneziawg-tools.git /opt/amnezia-tools
cd /opt/amnezia-tools/src
make
make install

```

## Использование awg-manager
```
./awg-manager.sh -u Username -c
```

## Выдача IP-адресов пользователям

При `-c` каждый пользователь получает первый свободный адрес из `SERVER_IP_PREFIX.2` … `SERVER_IP_PREFIX.254` (`.1` — сервер).
Адрес считается занятым, если он найден в любом из источников:

 - `Address` в конфигах пользователей `keys/<server>/<user>/<user>.conf`
 - `Address` / `AllowedIPs` в конфиге сервера `<server>.conf` (включая пиры без каталога ключей или добавленные вручную)
 - разрешённые IP работающего интерфейса (`awg show <server> allowed-ips`)

Учитываются только одиночные адреса (`/32` или без маски) из подсети `SERVER_IP_PREFIX`; маршрутизируемые подсети в `AllowedIPs` игнорируются.
Если вы меняете адрес пира вручную, держите `Address` в конфиге пользователя и `AllowedIPs` в конфиге сервера согласованными.

### IPv6

Если задан `SERVER_IP6_PREFIX`, каждый пользователь также получает IPv6-адрес с тем же номером хоста в шестнадцатеричном виде
(`10.10.90.10` → `fd10:10:90::a`), IPv6 DNS-серверы и `AllowedIPs = 0.0.0.0/0, ::/0`, так что IPv6-трафик
идёт через туннель, а не утекает мимо него. ULA-префикс (`fc…`/`fd…`) NAT-ится в IPv6-адрес сервера,
любой другой префикс маршрутизируется как есть (без NAT66): провайдер должен доставлять весь префикс на сервер
(см. [Oracle Cloud](#oracle-cloud)). Используйте префикс `/120` или короче: адреса пользователей — `<prefix>2` … `<prefix>fe`.
При инициализации скрипт также включает `net.ipv6.conf.all.forwarding` (и `accept_ra=2` на `SERVER_INTERFACE`,
если ядро обрабатывает там router advertisements, иначе включение forwarding привело бы к потере IPv6-маршрута по умолчанию).

Чтобы добавить IPv6 на существующий сервер, см. [Настройки применяются только к новым конфигам](#настройки-применяются-только-к-новым-конфигам):
добавьте `<prefix>1/128` в `Address` сервера и правила `ip6tables` (см. [Файрвол](#файрвол)),
`, <prefix>N/128` в `Address` каждого пользователя, IPv6 DNS в `DNS` и `, ::/0` в `AllowedIPs`.

## Файрвол

При инициализации в конфиг сервера записываются правила `PostUp`/`PostDown`, поэтому они существуют, только пока интерфейс поднят:

 - UDP-порт открывается в `INPUT` (IPv4 и IPv6);
 - трафик от клиентов к `SERVER_INTERFACE` и ответы обратно разрешаются в `FORWARD` (в образах вроде Ubuntu в Oracle Cloud цепочка `FORWARD` заканчивается `REJECT`);
 - новые соединения от `SERVER_INTERFACE` к клиентам отбрасываются в `FORWARD` (важно для публичного IPv6-префикса);
 - клиенты NAT-ятся (`MASQUERADE`) на `SERVER_INTERFACE`.

Правила `FORWARD` добавляются и для IPv6, если задан `SERVER_IP6_PREFIX`, правило IPv6 NAT — только для ULA-префикса.
Трафик между клиентами не разрешён.

При `SERVER_MODE=local` нет ни NAT, ни выхода наружу: единственное правило `FORWARD` разрешает трафик между клиентами
(`-i %i -o %i`), а конфиги пользователей не содержат `DNS` и включают в `AllowedIPs` только VPN-подсеть.

## Oracle Cloud

Заметки для инстанса Ubuntu в Oracle Cloud:

 - Образы Ubuntu там поставляются с правилами `iptables` в `/etc/iptables/rules.v4` (`netfilter-persistent`), которые завершают
   `INPUT` и `FORWARD` правилом `REJECT`. Правила `PostUp`, созданные при инициализации, вставляются перед ними, сохранять ничего не нужно.
 - Security List в VCN должен разрешать порт сервера: ingress UDP `SERVER_PORT` из `0.0.0.0/0` и `::/0`.
   Для ping также нужен ingress ICMP type 8; по умолчанию разрешены только типы 3 и 4.
 - Для IPv6 на инстансе нужны IPv6-префикс на VCN и подсети, маршрут `::/0` на Internet Gateway
   в таблице маршрутизации и egress-правило для `::/0` в Security List (по умолчанию разрешён только `0.0.0.0/0`).
 - Публичный `SERVER_IP6_PREFIX` должен быть назначен VNIC инстанса: Instance → Attached VNICs → VNIC →
   IPv6 Addresses → Assign IPv6 address → префикс (например, `/80`) из `/64` подсети. Oracle доставляет на инстанс
   только адреса, назначенные его VNIC: другие адреса `/64` подсети не работают даже с proxy NDP.
   Для назначенного префикса не нужны ни правило маршрутизации, ни отключение проверки source/destination.

## Решение проблем

### amneziawg-dkms не собирается на ядре 7.0

`amneziawg-dkms` 1.0.0 не собирается на новых ядрах Ubuntu (например, `7.0.0-*-oracle`, `7.0.0-*-generic`): `compat/compat.h`
по версии ядра решает, что `setup_udp_tunnel_sock()` принимает `struct socket *`, но эти ядра уже
принимают `struct sock *`. Исправьте `/usr/src/amneziawg-1.0.0/compat/compat.h`, чтобы тип аргумента выбирался по реальному
типу функции:

```diff
 #if LINUX_VERSION_CODE < KERNEL_VERSION(7, 1, 5)
 #include <net/udp_tunnel.h>
-#define setup_udp_tunnel_sock(net, sk, sock_cfg) setup_udp_tunnel_sock(net, sk->sk_socket, sock_cfg)
 #define udp_tunnel_sock_release(sk) udp_tunnel_sock_release(sk->sk_socket)
 #endif
 
+/* Select the argument type from the actual kernel API. */
+#include <net/udp_tunnel.h>
+#define setup_udp_tunnel_sock(net, sk, sock_cfg) \
+    setup_udp_tunnel_sock((net), \
+        _Generic(&setup_udp_tunnel_sock, \
+            void (*)(struct net *, struct socket *, struct udp_tunnel_sock_cfg *): (sk)->sk_socket, \
+            default: (sk)), \
+        (sock_cfg))
+
```

Затем пересоберите модуль, доконфигурируйте пакеты и не дайте `apt upgrade` вернуть непропатченные исходники:

```bash
sudo dkms remove amneziawg/1.0.0 --all
sudo dkms install amneziawg/1.0.0 -k $(uname -r)
sudo apt -f install
sudo modprobe amneziawg
sudo apt-mark hold amneziawg-dkms
```

При обновлениях ядра DKMS пересобирает модуль из пропатченных исходников.

### SSH отваливается во время сборки на инстансе с 1 ГБ памяти

Сборка модуля (или чего угодно через `apt` + компилятор) может исчерпать память на маленьких инстансах
(например, Oracle `E2.1.Micro`). Сначала добавьте swap:

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Использование amneziawg-go

Просто запустите:
```
amneziawg-go awg0
```
Это создаст интерфейс и уйдёт в фон. Чтобы удалить интерфейс, используйте обычный `ip link del awg0`, а если ваша система не поддерживает прямое удаление интерфейсов, можно удалить управляющий сокет `rm -f /var/run/amneziawg/awg0.sock` — после этого amneziawg-go завершится.

Чтобы запустить amneziawg-go без ухода в фон, передайте `-f` или `--foreground`:
```
amneziawg-go -f awg0
```
Когда интерфейс запущен, для его настройки можно использовать `awg-quick` из amneziawg-tools, а также обычные команды ip(8) и ifconfig(8).

## Установка

 - Скачайте скрипт [awg-manager.sh](https://raw.githubusercontent.com/bkeenke/awg-manager/master/awg-manager.sh) с GitHub
 - Инициализируйте сервер AmneziaWG: `./awg-manager.sh -i -s YOUR_SERVER_IP`
 - Добавьте пользователя: `./awg-manager.sh -c -u my_user -p > awg-client.conf`
 - Установите AmneziaVPN на клиенте
 - Запустите клиент с конфигом `awg-client.conf`
