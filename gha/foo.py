#!/usr/bin/env python3

import json
import os
import socket
import subprocess
import sys

from dnslib import DNSRecord, DNSHeader, DNSQuestion, QTYPE, RR, A

# Define the constant at the top of your script or in a configuration file
SCRIPT_NAME = os.path.splitext(os.path.basename(sys.argv[0]))[0]

def get_network_info():
    try:
        # Get IP address information
        addr_result = subprocess.run(['ip', '-j', 'addr'], capture_output=True, text=True)
        ip_info = json.loads(addr_result.stdout)

        network_config = {}
        prefix = f"{SCRIPT_NAME}-"
        for interface in ip_info:
            if interface['ifname'].startswith(prefix):
                # Extract domain prefix by removing the script name and hyphen
                domain_prefix = interface['ifname'][len(prefix):]
                for addr in interface['addr_info']:
                    if addr['family'] == 'inet':
                        ip_address = addr['local']
                        prefixlen = addr['prefixlen']
                        network = f"{ip_address.rsplit('.', 1)[0]}.0/{prefixlen}"
                        dns_server = f"{ip_address.rsplit('.', 1)[0]}.1"  # Assume first IP in network is DNS server
                        
                        network_config[interface['ifname']] = {
                            'domain': f"{domain_prefix}.internal",
                            'ip': ip_address,
                            'network': network,
                            'dns_server': dns_server
                        }
                        break
                else:
                    print(f"Warning: No IPv4 address found for {interface['ifname']}", file=sys.stderr)
        
        if not network_config:
            print(f"No interfaces with prefix '{prefix}' found.", file=sys.stderr)
        
        return network_config
    except Exception as e:
        print(f"Error getting network info: {e}", file=sys.stderr)
        return {}

def get_default_dns():
    try:
        result = subprocess.run(['resolvectl', 'dns'], capture_output=True, text=True)
        dns_servers = []
        for line in result.stdout.splitlines():
            if line.startswith('Global:'):
                servers = line.split(':')[1].strip().split()
                dns_servers = [server for server in servers if server != '127.53.0.53']  # Exclude our own proxy
                break  # We only need the Global DNS servers
        
        if not dns_servers:
            print("No global DNS servers found, using fallback", file=sys.stderr)
            return ['8.8.8.8']  # Fallback to Google DNS if no servers found
        
        return dns_servers
    except Exception as e:
        print(f"Error getting default DNS: {e}", file=sys.stderr)
        return ['8.8.8.8']  # Default to Google DNS in case of error

def forward_dns(request, server, port=53):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(5)  # Set a timeout of 5 seconds
    try:
        sock.sendto(request, (server, port))
        data, _ = sock.recvfrom(1024)
        return data
    except socket.timeout:
        print(f"Timeout while querying {server}:{port}", file=sys.stderr)
        return None
    finally:
        sock.close()

def handle_dns_request(data, addr, socket, network_config, default_dns):
    try:
        request = DNSRecord.parse(data)
        qname = str(request.q.qname)
        print(f"Received query for: {qname}", file=sys.stderr)
        
        for config in network_config.values():
            if qname.endswith(f"{config['domain']}."):
                # Strip the domain suffix for internal queries
                stripped_qname = qname[:-len(f"{config['domain']}.")-1]
                print(f"Stripping domain, new query: {stripped_qname}", file=sys.stderr)
                
                # Create a new request with the stripped name
                new_request = DNSRecord(DNSHeader(id=request.header.id, qr=0, aa=0, ra=0),
                                        q=DNSQuestion(stripped_qname, qtype=request.q.qtype))
                
                print(f"Forwarding internal query to DNS: {stripped_qname} -> {config['dns_server']}", file=sys.stderr)
                response_data = forward_dns(new_request.pack(), config['dns_server'])
                
                if response_data:
                    # Parse the response and modify it to use the original query name
                    response = DNSRecord.parse(response_data)
                    response.header.id = request.header.id
                    response.questions[0].qname = request.q.qname
                    for rr in response.rr:
                        rr.rname = request.q.qname
                    
                    socket.sendto(response.pack(), addr)
                    print(f"Sent modified response for {qname}", file=sys.stderr)
                else:
                    print(f"No response received for {stripped_qname}", file=sys.stderr)
                    # Send a failure response
                    response = request.reply()
                    response.header.rcode = 2  # SERVFAIL
                    socket.sendto(response.pack(), addr)
                return
        
        # If not an internal domain, forward to default DNS
        print(f"Forwarding query to default DNS: {qname} -> {default_dns[0]}", file=sys.stderr)
        response_data = forward_dns(data, default_dns[0])
        
        if response_data:
            socket.sendto(response_data, addr)
            print(f"Sent response for {qname}", file=sys.stderr)
        else:
            print(f"No response received for {qname}", file=sys.stderr)
            # Send a failure response
            response = request.reply()
            response.header.rcode = 2  # SERVFAIL
            socket.sendto(response.pack(), addr)
    except Exception as e:
        print(f"Error handling request: {e}", file=sys.stderr)

def usage(message):
        print(message, file=sys.stderr)
        print("docker network inspect <network-name>", file=sys.stderr)
        print("docker network connect <network-name> ${HOSTNAME}", file=sys.stderr)
        print("ip link add proxy-dns-<name> type dummy", file=sys.stderr)
        print("ip addr add <network-ip>/32 dev proxy-dns-<name>", file=sys.stderr)
        print("systemctl [re]start proxy-dns", file=sys.stderr)
        print("resolvectl flush-caches", file=sys.stderr)
        print("systemctl restart systemd-resolved", file=sys.stderr)

def main():
    network_config = get_network_info()
    if not network_config:
        usage("Failed to get network configuration. Exiting.")
        sys.exit(1)

    default_dns = get_default_dns()
    usage(f"Default DNS servers: {', '.join(default_dns)}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.53.0.53', 53))
    
    print("DNS Proxy running on 127.53.0.53:53", file=sys.stderr)
    print(f"Configured interfaces and domains:", file=sys.stderr)
    for interface, config in network_config.items():
        print(f"  {interface}: {config['domain']} -> {config['ip']} (Network: {config['network']}, DNS: {config['dns_server']})", file=sys.stderr)
    
    while True:
        try:
            data, addr = sock.recvfrom(1024)
            handle_dns_request(data, addr, sock, network_config, default_dns)
        except Exception as e:
            print(f"Error in main loop: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
