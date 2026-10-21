#!/usr/bin/env python3
import sys
import time
import pexpect

PUBLIC_KEYS = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIYXJ+KG1CkgLEwrgjASIkHgspER1OK+Befge16DKOgc alvaro.delabarra@agetic.gob.bo",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEW3LsZmGMuwdgnikoWu0PzAX+SIwrRvlTGAQtyUhI/O n306@debian"
]

def bootstrap(ip, username, password, hostname, static_ip=None):
    print(f"[*] Bootstrapping {hostname} at {ip} (user: {username})...")
    ssh_cmd = (
        f"ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
        f"-J n306@192.168.29.25 {username}@{ip}"
    )
    
    child = pexpect.spawn(ssh_cmd, timeout=30, encoding='utf-8')
    child.logfile = sys.stdout

    idx = child.expect([r'[Pp]assword:', pexpect.EOF, pexpect.TIMEOUT])
    if idx != 0:
        print(f"[!] Failed to get password prompt for {username}@{ip}")
        return False
    
    child.sendline(password)
    idx = child.expect([r'[$#]', r'[Pp]assword:', pexpect.EOF, pexpect.TIMEOUT])
    if idx != 0:
        print(f"[!] Password rejected for {username}@{ip}")
        return False
    
    print(f"\n[+] Logged in as {username}!")

    # Elevate to root via su -
    child.sendline("su -")
    idx = child.expect([r'[Pp]assword:', r'[$#]'])
    if idx == 0:
        child.sendline(password)
        child.expect(r'root@.*[#$]')
    print("\n[+] Gained root shell!")

    # Commands to run as root
    keys_str = "\\n".join(PUBLIC_KEYS)
    setup_commands = [
        # 1. Install sudo if missing
        "which sudo || (apt-get update && apt-get install -y sudo curl wget jq nftables)",
        
        # 2. Configure passwordless sudo for user and debian
        f"echo '{username} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-{username}",
        "echo 'debian ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-debian",
        "chmod 0440 /etc/sudoers.d/99-*",
        
        # 3. Create debian user if not exists
        "id debian || (useradd -m -s /bin/bash -G sudo debian && echo 'debian:debian' | chpasswd)",
        
        # 4. Inject SSH keys for username, debian, root
        f"mkdir -p /home/{username}/.ssh /home/debian/.ssh /root/.ssh",
        f"printf '{keys_str}\\n' > /home/{username}/.ssh/authorized_keys",
        f"printf '{keys_str}\\n' > /home/debian/.ssh/authorized_keys",
        f"printf '{keys_str}\\n' > /root/.ssh/authorized_keys",
        f"chown -R {username}:{username} /home/{username}/.ssh",
        "chown -R debian:debian /home/debian/.ssh",
        f"chmod 700 /home/{username}/.ssh /home/debian/.ssh /root/.ssh",
        f"chmod 600 /home/{username}/.ssh/authorized_keys /home/debian/.ssh/authorized_keys /root/.ssh/authorized_keys",
        
        # 5. Hostname
        f"hostnamectl set-hostname {hostname}",
        f"sed -i '/127.0.1.1/d' /etc/hosts",
        f"echo '127.0.1.1 {hostname}' >> /etc/hosts",
        
        # 6. Network configuration if static_ip given
        f"""cat << 'NETEOF' > /etc/network/interfaces
# Interface loopback
auto lo
iface lo inet loopback

# Red privada cluster
auto enp2s0
iface enp2s0 inet static
    address {static_ip or ip}/24
    gateway 10.100.29.30
    dns-nameservers 10.100.29.30 8.8.8.8
NETEOF""",
        "echo 'Bootstrap commands finished successfully'"
    ]

    for cmd in setup_commands:
        child.sendline(cmd)
        child.expect(r'root@.*[#$]', timeout=60)

    child.sendline("exit") # exit root
    child.expect(r'[$#]')
    child.sendline("exit") # exit ssh
    child.expect(pexpect.EOF)
    print(f"\n[+] Successfully bootstrapped {hostname} ({ip})!")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print("Usage: bootstrap_node.py <IP> <USER> <PASSWORD> <HOSTNAME> [STATIC_IP]")
        sys.exit(1)
    ip = sys.argv[1]
    user = sys.argv[2]
    pw = sys.argv[3]
    host = sys.argv[4]
    st_ip = sys.argv[5] if len(sys.argv) > 5 else ip
    success = bootstrap(ip, user, pw, host, st_ip)
    sys.exit(0 if success else 1)
