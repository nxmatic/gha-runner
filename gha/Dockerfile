ARG NODE_VERSION=22.3.0-alpine3.19 #16.13.1-alpine3.14
ARG UBUNTU_VERSION=noble # 24.04 (mantic - 23.10)
ARG FETCH_MDNS_PUBLISHER_SOURCE_TIMESTAMP=0

FROM node:${NODE_VERSION} AS kms-builder

WORKDIR /app

COPY --link /kms/package*.json ./

RUN npm ci

FROM node:${NODE_VERSION} AS kms

WORKDIR /app

COPY --link --from=kms-builder /app ./

COPY --link /kms/index.js /kms/config.json ./

EXPOSE 3000

CMD ["node","index.js"]

FROM jrei/systemd-ubuntu:${UBUNTU_VERSION} AS env

ARG GITHUB_RUNNER_VERSION=latest
ARG DEBIAN_FRONTEND=noninteractive

RUN <<~
    : install required cli and tools
    apt-get -y update
    apt-get -y install      \
      bash                  \
      git gh jq             \
      curl ca-certificates 
~

SHELL [ "/usr/bin/env", "-S", "bash", "-ex", "-o", "pipefail", "-c" ]
ENV PS4="+ "

WORKDIR /runner

RUN --mount=type=secret,id=GITHUB_TOKEN <<~
    : fetch runtime from github release
    gh:arch() {
      case $(uname -m) in
        aarch64) echo "arm64";;
        x86_64) echo "x64";;
        *) echo "cannot map arch" && exit 1;;
      esac
    }
    trap "rm -f /tmp/runner.tgz" EXIT
    export GH_TOKEN=$(cat /run/secrets/GITHUB_TOKEN)
    gh extension install chmouel/gh-get-asset
    gh get-asset -s -o /tmp/runner.tgz actions/runner linux-$( gh:arch )
    gunzip - < /tmp/runner.tgz |
      tar xf -
~

FROM jrei/systemd-ubuntu:${UBUNTU_VERSION} AS systemd-ubuntu

ARG DEBIAN_FRONTEND=noninteractive

RUN <<~
    : install required cli and tools
    apt-get -y update
    apt-get -y install      \
      bash                  \
      gpg                   \
      git gh jq             \
      curl ca-certificates 
~

SHELL [ "/usr/bin/env", "-S", "bash", "-ex", "-o", "pipefail", "-c" ]
ENV PS4="+ "

RUN <<~
    : add tools for debugging
    apt-get update
    apt-get -y install      \
      emacs-nox             \
      bind9-dnsutils        \
      lsof                  \
      tshark
~

FROM env AS proxy-mdns-builder

ARG FETCH_SOURCES_TIMESTAMP=0

RUN <<~
  : Install golang tools
  apt-get -y install golang
~

RUN --mount=type=secret,id=GITHUB_TOKEN <<~
  : Clone nxmatic/go-mdns-publisher repo
  export GH_TOKEN=$(cat /run/secrets/GITHUB_TOKEN)
  git config --global gh-get.root /source
  gh extension install pomdtr/gh-get
  gh get nxmatic/go-mdns-publisher
~

WORKDIR /source/github.com/nxmatic/go-mdns-publisher

RUN <<~
  : On version ${FETCH_MDNS_PUBLISHER_SOURCE_TIMESTAMP}
  git fetch
  git checkout feature/docker-build

  : Build go-mdns-publisher
  go get github.com/docker/docker/client
  go build main.go
~

FROM systemd-ubuntu AS proxy-dns

# Systemd Resolved

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 CMD /usr/local/bin/check-resolved || exit 1

RUN <<'~'
  : Install required tools
  apt-get update
  apt-get install -y \
    iproute2 \
    python3 \
    python3-dnslib \
    python3-pip \
    python3-setuptools \
~

RUN <<'~'
  : Install signing docker key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  : Add the repository to Apt sources
  cat <<! | cut -c 3- | tee /etc/apt/sources.list.d/docker.list
  deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable
!
  : Install packages
  apt-get -y update
  apt-get -y install --no-install-recommends --allow-unauthenticated \
    docker-ce-cli docker-buildx-plugin \
    docker-compose-plugin containerd.io

  : add related groups
  group:add() {
    name=$1
    id=$2
    group=$( getent group | awk -F: "\$3 == $id { print }" )

    if [[ -z "$group" ]]; then
      groupadd -g $id $name
    fi
  }       

  group:add docker 999
  group:add podman 1000

  : Disable useless services
  systemctl disable containerd
~

COPY --chmod=644 <<'000-proxy-dns.conf' /etc/systemd/resolved.conf.d/
[Resolve]
Cache=yes
CacheFromLocalhost=yes
Domains=dns.podman
DNS=127.53.0.53 8.8.8.8
DNSSEC=no
DNSStubListener=yes
FallbackDNS=1.1.1.1
000-proxy-dns.conf

COPY --chmod=755 <<'proxy-dns' <<'relink-etc-resolv-conf' <<'check-resolved' /usr/local/sbin/
#!/usr/bin/env python3

import os
import pdb
import sys
import json
import select
import socket
import subprocess
import traceback
import threading

from dnslib import DNSRecord, DNSHeader, DNSQuestion, QTYPE, RR, RCODE, A

from collections import OrderedDict
from time import time

from dnslib import DNSRecord, RCODE, QTYPE
from time import time
from collections import OrderedDict
import sys

from dnslib import DNSRecord, RCODE, QTYPE
from time import time
from collections import OrderedDict
import sys

class DNSCache:
    def __init__(self, max_size=1000, default_ttl=60):
        self.cache = OrderedDict()
        self.max_size = max_size
        self.default_ttl = default_ttl

    def evict_if_expired(self, key):
        qname, qtype = key
        dns_server, response, cache_time = self.cache[key]
        current_time = time()
        elapsed = int(current_time - cache_time)

        # If it's a SERVFAIL response, we don't need to check TTL
        if response.header.rcode == RCODE.SERVFAIL:
            if elapsed > self.default_ttl:
                print(f"Evicted {qname} ({qtype}) from cache due to TTL expiration", file=sys.stderr)
                del self.cache[key]
                return None
        # Check if the entire response has expired
        elif all(rr.ttl <= elapsed for rr in response.rr):
            print(f"Evicted {qname} ({qtype}) from cache due to TTL expiration", file=sys.stderr)
            del self.cache[key]
            return None

        return (dns_server, response, elapsed)

        
    def get(self, qname, qtype, request_id):
        key = (qname, qtype)
        if key not in self.cache:
            print(f"Not found {qname} ({qtype}) in cache", file=sys.stderr)
            return None

        rec = self.evict_if_expired(key)
        if rec is None:
            return None
        dns_server, response, elapsed = rec

        # Create a copy of the response to modify
        new_response = DNSRecord.parse(response.pack())

        # Update TTLs
        for rr in new_response.rr:
            rr.ttl = max(0, rr.ttl - elapsed)

        # Update response ID
        new_response.header.id = request_id

        DNSHandler.print_response(dns_server, new_response)

        return (dns_server, new_response)

    def push(self, qname, qtype, dns_server, response):
        key = (qname, qtype)
        if len(self.cache) >= self.max_size:
            self.cache.popitem(last=False)
        
        # Ensure we're storing a DNSRecord object
        if isinstance(response, bytes):
            response = DNSRecord.parse(response)
        elif not isinstance(response, DNSRecord):
            print(f"Error: Unexpected response type in cache push: {type(response)}", file=sys.stderr)
            return

        self.cache[key] = (dns_server, response, time())
        print(f"Cached Response for {qname} ({qtype}) from {dns_server}:", file=sys.stderr)
        DNSHandler.print_response(dns_server, response)

class DNSHandler:
    def __init__(self, network_info, default_dns_servers):
        self.network_info = network_info
        self.default_dns_servers = default_dns_servers
        self.cache = DNSCache()

    def handle_request(self, data, addr, socket):
        try:
            request = DNSRecord.parse(data)
            qname = str(request.q.qname)
            qtype = request.q.qtype
            print(f"Received query for: {qname} (Type: {QTYPE.get(qtype)})", file=sys.stderr)

            cached_entry = self.cache.get(qname, qtype, request.header.id)
            if cached_entry:
                (dns_server, response) = cached_entry
                socket.sendto(response.pack(), addr)
                print(f"Sent cached response for: {qname}", file=sys.stderr)
                return

            if '.' not in qname or qname.count('.') == 1 and qname.endswith('.'):
                (dns_server, response) = self.handle_host_query(request)
            elif qname.endswith('.internal') or qname.endswith('.internal.'):
                (dns_server, response) = self.handle_host_query(request)
            elif qname.endswith('.dns.podman') or qname.endswith('.dns.podman.'):
                (dns_server, response) = self.handle_host_query(request)
            else:
                (dns_server, response) = self.handle_domain_query(request)

            if response is None:
                print(f"No valid response received for {qname} from any DNS server", file=sys.stderr)
                (dns_server, response) = self.create_servfail_response(request)

            self.cache.push(qname, qtype, dns_server, response)
            socket.sendto(response.pack(), addr)
            print(f"Sent response for: {qname}", file=sys.stderr)
        except Exception as e:
            print(f"Error handling request: {e}", file=sys.stderr)
            traceback.print_exc()
             
    def handle_host_query(self, request):
        last_response = None
        for config in self.network_info.values():
            dns_server = config['dns_server']
            (dns_server, response) = self.query_internal_dns(request, dns_server)
            if response:
                last_response = (dns_server, response)
                if len(response.rr) > 0:
                    return last_response

        if last_response:
            print(f"Only empty responses received for {request.q.qname} from internal DNS servers", file=sys.stderr)
            return last_response

        print(f"No response received for {request.q.qname} from any internal DNS server", file=sys.stderr)
        return self.create_servfail_response(request)

    def handle_domain_query(self, request):
        qname = str(request.q.qname)
        for config in self.network_info.values():
            domain_suffix = f".{config['domain']}."
            if qname.endswith(domain_suffix):
                stripped_qname = qname[:-len(domain_suffix)] or '@'
                return self.query_internal_dns(request, config['dns_server'], stripped_qname)

        return self.query_default_dns(request)

    def query_internal_dns(self, request, dns_server, qname=None):
        qname = qname or request.q.qname
        print(f"Querying internal DNS: {qname} -> {dns_server}", file=sys.stderr)

        new_request = DNSRecord(DNSHeader(id=request.header.id, qr=0, aa=0, ra=0),
                                q=DNSQuestion(qname, qtype=request.q.qtype))

        response = self.forward_dns(new_request.pack(), dns_server)
    
        if not response:
            print(f"No response received from {dns_server} for {qname}", file=sys.stderr)
            return self.create_servfail_response(request)

        try:
            response.header.id = request.header.id
            response.questions[0].qname = request.q.qname
            for rr in response.rr:
                rr.rname = request.q.qname
                
            return ( dns_server, response )
        except Exception as e:
            print(f"Error parsing response from {dns_server}: {e}", file=sys.stderr)
            return self.create_servfail_response(request)

    def query_default_dns(self, request):
        qname = str(request.q.qname)
        for dns_server in self.default_dns_servers:
            print(f"Forwarding query to default DNS: {qname} -> {dns_server}", file=sys.stderr)
            response = self.forward_dns(request.pack(), dns_server)
            if response:
                return ( dns_server, response )
            print(f"No response received from {dns_server} for {qname}", file=sys.stderr)
        return self.create_servfail_response(request)

    def forward_dns(self, data, dns_server, max_retries=3):
        for attempt in range(max_retries):
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sock.settimeout(5)  # 5 second timeout
                sock.sendto(data, (dns_server, 53))
                response_bytes, _ = sock.recvfrom(1024)
                try:
                    return DNSRecord.parse(response_bytes)
                except Exception as e:
                    print(f"Error parsing DNS response from {dns_server}: {e}", file=sys.stderr)
                    return None
            except socket.timeout:
                print(f"Timeout while querying {dns_server}", file=sys.stderr)
            except Exception as e:
                print(f"Error in forward_dns: {e}", file=sys.stderr)
            finally:
                sock.close()
        return None

    @staticmethod
    def print_response(dns_server, response):
        print(f"Response from {dns_server}", file=sys.stderr)
        if response.header.rcode == RCODE.SERVFAIL:
            print(f"  SERVFAIL response from {dns_server}", file=sys.stderr)
            return
        if len(response.rr) == 0:
            print(f"  No records in response", file=sys.stderr)
        for rr in response.rr:
            record_type = QTYPE.get(rr.rtype)
            print(f"  {rr.rname} {record_type} {rr.rdata} (TTL: {rr.ttl})", file=sys.stderr)

    @staticmethod
    def create_servfail_response(request):
        response = request.reply() if request else DNSRecord()
        response.header.rcode = RCODE.SERVFAIL
        return ( '127.0.0.1', response )

SCRIPT_NAME = os.path.splitext(os.path.basename(sys.argv[0]))[0]

def get_all_networks():
    try:
        result = subprocess.run(['docker', 'network', 'ls', '--format', '{{.Name}}'], capture_output=True, text=True, check=True)
        return result.stdout.strip().split('\n')
    except subprocess.CalledProcessError as e:
        print(f"Error listing Docker networks: {e}", file=sys.stderr)
        return []

def get_container_id():
    # Try to get the HOSTNAME from environment variable
    hostname = os.environ.get('HOSTNAME')
    
    # If HOSTNAME is not set in the environment, fall back to the hostname command
    if not hostname:
        try:
            result = subprocess.run(['hostname'], capture_output=True, text=True, check=True)
            hostname = result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print(f"Error running hostname command: {e}", file=sys.stderr)
        except Exception as e:
            print(f"Unexpected error getting hostname: {e}", file=sys.stderr)
    
    return hostname

def get_container_networks(container_id):
    try:
        result = subprocess.run(['docker', 'container', 'inspect', '--format=json', container_id], capture_output=True, text=True)
        container_info = json.loads(result.stdout)
        if container_info and len(container_info) > 0:
            networks = container_info[0].get('NetworkSettings', {}).get('Networks', {})
            return networks
        return {}
    except Exception as e:
        print(f"Error getting container networks: {e}", file=sys.stderr)
        return {}

def connect_to_networks(container_id):
    all_networks = get_all_networks()
    current_networks = get_container_networks(container_id)

    for network in all_networks:
        if network == 'bridge':
            continue
        if network not in current_networks:
            try:
                subprocess.run(['docker', 'network', 'connect', network, container_id], check=True)
                print(f"Connected to network: {network}", file=sys.stderr)
            except subprocess.CalledProcessError as e:
                print(f"Failed to connect to network {network}: {e}", file=sys.stderr)

    # After connecting to new networks, get updated network info
    return get_network_info(container_id)

def get_network_info(container_id):
    try:
        # Get IP address information
        addr_result = subprocess.run(['ip', '-j', 'addr'], capture_output=True, text=True)
        ip_info = json.loads(addr_result.stdout)

        # Get container networks
        container_networks = get_container_networks(container_id)

        network_info = {}
        prefix = f"{SCRIPT_NAME}-"
        
        for interface in ip_info:
            if interface['ifname'].startswith(prefix):
                domain_prefix = interface['ifname'][len(prefix):]
                for addr in interface['addr_info']:
                    if addr['family'] == 'inet':
                        ip_address = addr['local']
                        prefixlen = addr['prefixlen']
                        network = f"{ip_address.rsplit('.', 1)[0]}.0/{prefixlen}"
                        dns_server = f"{ip_address.rsplit('.', 1)[0]}.1"
                        
                        network_info[interface['ifname']] = {
                            'domain': f"{domain_prefix}.internal",
                            'ip': ip_address,
                            'network': network,
                            'dns_server': dns_server
                        }
                        break
                else:
                    print(f"Warning: No IPv4 address found for {interface['ifname']}", file=sys.stderr)
        
        # Add container networks
        for net_name, net_info in container_networks.items():
            network_info[f"docker-{net_name}"] = {
                'domain': f"{net_name.replace('compose_', '')}.internal",
                'ip': net_info.get('IPAddress', '0.0.0.0'),
                'network': net_info.get('NetworkID', ''),
                'dns_server': net_info.get('Gateway', '')  # Docker's embedded DNS
            }
        
        if not network_info:
            print(f"No interfaces with prefix '{prefix}' or container networks found.", file=sys.stderr)
        
        return network_info
    except Exception as e:
        print(f"Error getting network info: {e}", file=sys.stderr)
        return {}

def get_default_dns_servers():
    try:
        result = subprocess.run(['resolvectl', 'status'], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if line.strip().startswith('DNS Servers:'):
                servers = line.split(':')[1].strip().split()
                return [server for server in servers if server != '127.53.0.53']  # Exclude our own proxy
        return ['8.8.8.8']  # Default to Google DNS if no servers found
    except Exception as e:
        print(f"Error getting default DNS: {e}", file=sys.stderr)
        return ['8.8.8.8']  # Default to Google DNS in case of error

def flush_dns_and_restart_resolved():
    try:
        print("Flushing DNS caches...", file=sys.stderr)
        subprocess.run(['resolvectl', 'flush-caches'], check=True)
        print("DNS caches flushed", file=sys.stderr)

        print("Restarting systemd-resolved...", file=sys.stderr)
        subprocess.run(['systemctl', 'restart', 'systemd-resolved'], check=True)
        print("systemd-resolved restarted", file=sys.stderr)
    except subprocess.CalledProcessError as e:
        print(f"Error flushing DNS or restarting systemd-resolved: {e}", file=sys.stderr)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)

def listen_to_dns_requests(network_info):
    sockets = []
    
    # UDP sockets
    sock_udp_loopback = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock_udp_container = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    sock_udp_loopback.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock_udp_container.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    sock_udp_loopback.bind(('127.53.0.53', 53))
    sock_udp_container.bind(('0.0.0.0', 53))
    
    sockets.extend([sock_udp_loopback, sock_udp_container])
    
    # TCP sockets for each discovered IP (excluding loopback)
    for interface, config in network_info.items():
        ip_address = config['ip']
        if not ip_address.startswith('127.'):  # Exclude loopback addresses
            try:
                sock_tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock_tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock_tcp.bind((ip_address, 53))
                sock_tcp.listen(5)
                sockets.append(sock_tcp)
                print(f"Listening on TCP {ip_address}:53 for interface {interface}", file=sys.stderr)
            except Exception as e:
                print(f"Failed to bind TCP socket to {ip_address}:53 for interface {interface}: {e}", file=sys.stderr)
    
    return sockets

def tcp_thread_entry_point(dnsHandler,addr,socket):
    try:
        while True:
            # Read the length of the DNS message (first two bytes)
            length_bytes = socket.recv(2)
            if not length_bytes:
                break
            length = int.from_bytes(length_bytes, byteorder='big')
            
            # Read the actual DNS message
            data = socket.recv(length)
            if len(data) != length:
                break
            
            # Process the DNS query
            dnsHandler.handle_request(data, addr, socket)
    except Exception as e:
        print(f"Error handling TCP socketection from {addr}: {e}", file=sys.stderr)
    finally:
        socket.close()
    


def main():
    container_id = get_container_id()
    if not container_id:
        print("Failed to determine container ID", file=sys.stderr)
        return

    network_info = connect_to_networks(container_id)
    if not network_info:
        print("Failed to get network configuration. Exiting.", file=sys.stderr)
        sys.exit(1)

    default_dns_servers = get_default_dns_servers()
    print(f"Default DNS servers: {', '.join(default_dns_servers)}", file=sys.stderr)

    # Print network configuration
    for net_name, net_config in network_info.items():
        print(f"Network: {net_name}")
        for key, value in net_config.items():
            print(f"  {key}: {value}")

    print("DNS Proxy running on 127.53.0.53:53 and discovered IP addresses", file=sys.stderr)
    print("Configured interfaces and domains:", file=sys.stderr)
    for interface, config in network_info.items():
        print(f"  {interface}: {config['domain']} -> {config['ip']} (Network: {config['network']}, DNS: {config['dns_server']})", file=sys.stderr)

    print("Listening for DNS requests", file=sys.stderr)
    sockets = listen_to_dns_requests(network_info)

    print("Flushing and restarting resolved", file=sys.stderr)
    flush_dns_and_restart_resolved()

    dnsHandler = DNSHandler(network_info, default_dns_servers)

    while True:
        try:
            # Use select to wait for data on any of the sockets
            readable, _, _ = select.select(sockets, [], [])

            for sock in readable:
                if sock.type == socket.SOCK_DGRAM:
                    # Handle UDP
                    data, addr = sock.recvfrom(1024)
                    dnsHandler.handle_request(data, addr, sock)
                elif sock.type == socket.SOCK_STREAM:
                    # Handle TCP
                    conn, addr = sock.accept()
                    threading.Thread(target=tcp_thread_entry_point, args=(dnsHandler, addr, conn)).start()

        except Exception as e:
            print(f"Error in main loop: {e}", file=sys.stderr)
            print("Full traceback:")
            traceback.print_exc()

if __name__ == "__main__":
    main()
proxy-dns
#!/usr/bin/env -S bash -xe -o pipefail
cp /etc/resolv.conf /etc/resolv.conf~container;
umount /etc/resolv.conf || true; rm -f /etc/resolv.conf
ln -fs /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
relink-etc-resolv-conf
#!/usr/bin/env -S bash -e -o pipefail
systemctl is-active --quiet systemd-resolved
check-resolved

COPY --chmod=644 <<'proxy-dns.service' <<'relink-etc-resolv-conf.service' /etc/systemd/system/
[Unit]
Description=Custom DNS Proxy
After=network.target

[Service]
Environment=DOCKER_HOST=tcp://host.containers.internal:2375
ExecStart=/usr/local/sbin/proxy-dns
Restart=always
User=root

[Install]
WantedBy=multi-user.target
proxy-dns.service
[Unit]
Description=Re-link resolv.conf to resolved stub
DefaultDependencies=no
Before=sysinit.target local-fs.target
ConditionPathExists=/etc/resolv.conf

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/relink-etc-resolv-conf
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
relink-etc-resolv-conf.service

# Systemd journactl configuration override

COPY --chmod=644 <<'console' /etc/systemd/journald.conf.d/
[Journal]
ForwardToConsole=yes
MaxLevelConsole=info
console

RUN <<'~'
  : Enable systemd-networkd
  systemctl enable systemd-networkd
  systemctl disable systemd-networkd-wait-online

  : Enable systemd-resolved
  systemctl enable systemd-resolved

  : Enable relink-etc-resolv-conf
  systemctl enable proxy-dns
  systemctl enable relink-etc-resolv-conf
~

FROM proxy-dns AS runner

ENV RUNNER_ADDITIONAL_FLAGS ""
ENV RUNNER_INTERNAL_DOMAIN ""
ENV RUNNER_GOPROXY ""
ENV RUNNER_LABELS ""
ENV RUNNER_NAME ""
ENV RUNNER_REGISTER_TO ""
ENV RUNNER_WORKDIR ""

RUN <<'~'
  : install required dependencies
  set -ex

  apt-get update
  apt-get -y install \
    apt-transport-https \
    apt-utils \
    autoconf \
    avahi-utils \
    bash \
    build-essential \
    bzip2 \
    ca-certificates \
    clang \
    chromium-browser \
    cmake \
    curl \
    dirmngr \
    dumb-init \
    gcc \
    gettext \
    gettext \
    git \
    gnupg \
    gosu \
    gpg-agent \
    inetutils-ping \
    jq \
    libcurl4 \
    libcurl4-openssl-dev \
    libpq-dev \
    locales \
    make \
    nodejs \
    openssh-client \
    perl \
    psmisc \
    rsync \
    software-properties-common \
    sudo \
    tar \
    unzip \
    wget \
    zip \
    zlib1g \
    zlib1g-dev \
    zstd

  : disable useless services
  systemctl disable postfix
  systemctl disable snapd
~

RUN <<'~'
  : install firefox and the geckodriver
  apt-get update
  apt-get install -y software-properties-common
  add-apt-repository ppa:mozillateam/ppa
  
  # Create preferences to prioritize Mozilla PPA version over snap
  cat <<! > /etc/apt/preferences.d/mozilla-firefox
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
!
  apt-get update
  apt-get -y install firefox-geckodriver
~

SHELL [ "/usr/bin/env", "-S", "bash", "-ex", "-o", "pipefail", "-c" ]
ENV PS4="+ "

RUN <<'~'
  : Adding focal as packages source for fetching libssl1.1 required by the runner
  sed -e "s/mantic/focal/g" </etc/apt/sources.list | tee /etc/apt/sources.list.d/focal.list
  apt-get -y update
~

# add runner user
RUN <<'~'
  : "Add runner user:"

  useradd -mr -d /home/runner -u 1001 -G 999,1000,sudo runner

  echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
~

# Install runner's runtime from env stage
COPY --from=env --chown=runner:runner /runner/ /home/runner/

RUN <<'~'
  bash -x -o pipefail /home/runner/bin/installdependencies.sh
~


# Systemd GHA runner service

COPY --chmod=644 <<'~' /etc/systemd/system/gha-runner.service
[Unit]
Description=GHA runner docker entrypoint
After=network.target

[Service]
Type=simple
User=runner
ExecStart=/home/runner/entrypoint.sh
Restart=always

[Install]
WantedBy=multi-user.target
~

COPY --chmod=644 <<'~' /etc/systemd/system/gha-runner.service.d/override.conf
[Service]
Environment=SYSTEMD_IGNORE_CHROOT=1
~

RUN <<'~'
  : Enable gha-runner
  systemctl enable gha-runner
~

# run as user
USER runner
WORKDIR /home/runner/

# set mountpoints
VOLUME /home/runner/.m2/repository
VOLUME /home/runner/.m2/build-cache

RUN <<~
    : create mountpoints with the right permission
    mkdir -p \
      ~/.m2/repository  \
      ~/.m2/build-cache
~

COPY --chown=runner:runner --chmod=755 <<'entrypoint.sh' <<'runsvc.sh' ./
#!/usr/bin/env -S bash -ex -o pipefail

env=( ADDITIONAL_FLAGS
      INTERNAL_DOMAIN
      GOPROXY
      LABELS
      NAME
      PROJECT_NAME
      REGISTER_TO
      WORKDIR
    )

set -a
source <( sudo cat /proc/1/environ | tr '\0' '\n' | grep -E "^RUNNER_($(IFS='|'; echo "${env[*]}"))=" )

KMS_URL=http://kms.gha.${RUNNER_PROJECT_NAME:-develop}.${RUNNER_INTERNAL_DOMAIN:-internal}:3000
GOPROXY=${RUNNER_GOPROXY}
set +a

cd ~runner

:register:workdir() {
  echo ${RUNNER_WORKDIR:-work}
}

:register:name() {
  echo ${RUNNER_NAME:-runner}
}

:register:to() {
  echo ${RUNNER_REGISTER_TO}
}

:register:labels() {
  echo ${RUNNER_LABELS}
}

:kms:server:path() {
  local service=$1
  local path=${RUNNER_REGISTER_TO}/$service

  if [[ "${RUNNER_REGISTER_TO}" == *\/* ]]; then
    path=repo/${path}
  fi

  echo $path
}

:kms:register:token() {
  curl -s ${KMS_URL}/$( :kms:server:path registration-token)
}

:kms:remove:token() {
  curl -s ${KMS_URL}/$( :kms:server:path remove-token)
}

register() {
    bash -x ./config.sh \
      --name $( :register:name ) \
      --work $( :register:workdir ) \
      --unattended \
      --disableupdate \
      --url "https://github.com/$( :register:to )" \
      --token $( :kms:register:token ) \
      --labels "$( :register:labels )" \
      ${RUNNER_ADDITIONAL_FLAGS} 
}

remove() {
  bash -x ./config.sh remove --token "$( :kms:remove:token )"
}

register

trap 'remove' EXIT

trap 'exit 130' INT
trap 'exit 143' TERM

./runsvc.sh "$*" &

wait $!
entrypoint.sh
#!/usr/bin/env -S bash -ex -o pipefail

# convert SIGTERM signal to SIGINT
# for more info on how to propagate SIGTERM to a child process see: http://veithen.github.io/2014/11/16/sigterm-propagation.html
trap 'kill -INT $PID' TERM INT

if [ -f ".path" ]; then
    # configure
    export PATH=`cat .path`
    echo ".path=${PATH}"
fi

# insert anything to setup env when running as a service

# run the host process which keep the listener alive
./externals/node20/bin/node ./bin/RunnerService.js &
PID=$!
wait $PID
trap - TERM INT
    wait $PID
runsvc.sh

# Should run root for launching systemd and we start the runner as a systemd service

#ENTRYPOINT ["/home/runner/entrypoint.sh"]
USER root


