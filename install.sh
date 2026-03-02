#!/bin/bash
set -euo pipefail

# Ubuntu Cloud Image Desktop VM Installer for KVM
# Usage: ./install.sh [OPTIONS]

VERSION="1.0.0"
UBUNTU_VERSION="24.04"
UBUNTU_CODENAME="noble"

# Default values
DEFAULT_HOSTNAME="ubuntu-desktop"
DEFAULT_USERNAME="user"
DEFAULT_FULLNAME="Ubuntu User"
DEFAULT_VCPUS="4"
DEFAULT_RAM="8192"
DEFAULT_DISK="50"
DEFAULT_VM_NAME="ubuntu-desktop-vm"
DEFAULT_DESKTOP="ubuntu-desktop"
DEFAULT_BRIDGE=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Ubuntu Cloud Image Desktop VM Installer for KVM v${VERSION}

Usage: $0 [OPTIONS]

Options:
    -h, --hostname      VM hostname (default: ${DEFAULT_HOSTNAME})
    -u, --username      Username for the VM (default: ${DEFAULT_USERNAME})
    -f, --fullname      Full name of the user (default: ${DEFAULT_FULLNAME})
    -p, --password      User password (required for install)
    -c, --vcpus         Number of vCPUs (default: ${DEFAULT_VCPUS})
    -r, --ram           RAM size in MB (default: ${DEFAULT_RAM})
    -d, --disk          Disk size in GB (default: ${DEFAULT_DISK})
    -n, --name          Virtual machine name (default: ${DEFAULT_VM_NAME})
    -e, --desktop       Desktop environment package (default: ${DEFAULT_DESKTOP})
    -b, --bridge        Host bridge for VM network (e.g., br0). If not specified,
                        uses the default libvirt NAT network.
    --remove            Remove the VM and all associated storage
    --help              Show this help message
    --version           Show version

Examples:
    $0 -h mydesktop -u myuser -f "John Doe" -p mypassword -c 4 -r 8192 -d 100 -n my-vm
    $0 -n my-vm -p mypassword --bridge br0
    $0 --remove -n my-vm

The script will install the following software automatically:
    - Google Chrome
    - Docker
    - Tailscale
    - Node.js (latest LTS)
    - VS Code
    - OpenClaw

EOF
    exit 0
}

show_version() {
    echo "Ubuntu Cloud Image Desktop VM Installer v${VERSION}"
    exit 0
}

# Parse command line arguments
HOSTNAME="${DEFAULT_HOSTNAME}"
USERNAME="${DEFAULT_USERNAME}"
FULLNAME="${DEFAULT_FULLNAME}"
PASSWORD=""
VCPUS="${DEFAULT_VCPUS}"
RAM="${DEFAULT_RAM}"
DISK="${DEFAULT_DISK}"
VM_NAME="${DEFAULT_VM_NAME}"
DESKTOP="${DEFAULT_DESKTOP}"
BRIDGE="${DEFAULT_BRIDGE}"
REMOVE_VM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -f|--fullname)
            FULLNAME="$2"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -c|--vcpus)
            VCPUS="$2"
            shift 2
            ;;
        -r|--ram)
            RAM="$2"
            shift 2
            ;;
        -d|--disk)
            DISK="$2"
            shift 2
            ;;
        -n|--name)
            VM_NAME="$2"
            shift 2
            ;;
        -e|--desktop)
            DESKTOP="$2"
            shift 2
            ;;
        -b|--bridge)
            BRIDGE="$2"
            shift 2
            ;;
        --remove)
            REMOVE_VM=true
            shift
            ;;
        --help)
            usage
            ;;
        --version)
            show_version
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ "${REMOVE_VM}" == false ]] && [[ -z "${PASSWORD}" ]]; then
    log_error "Password is required. Use -p or --password to specify."
    exit 1
fi

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    for cmd in virsh virt-install qemu-img wget cloud-localds; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing missing dependencies..."
        apt-get update
        apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cloud-image-utils wget
    fi

    # Ensure libvirtd is running
    if ! systemctl is-active --quiet libvirtd; then
        log_info "Starting libvirtd service..."
        systemctl start libvirtd
        systemctl enable libvirtd
    fi
}

# Remove VM and associated storage
remove_vm() {
    local vm_name="$1"
    local work_dir="/var/lib/libvirt/images/${vm_name}"

    log_info "Removing virtual machine: ${vm_name}"

    # Check if VM exists
    if ! virsh dominfo "${vm_name}" &> /dev/null; then
        log_warn "VM '${vm_name}' does not exist in libvirt"
    else
        # Stop VM if running
        if virsh domstate "${vm_name}" 2>/dev/null | grep -q "running"; then
            log_info "Stopping VM '${vm_name}'..."
            virsh destroy "${vm_name}" 2>/dev/null || true
        fi

        # Undefine VM and remove managed storage
        log_info "Undefining VM '${vm_name}' and removing storage..."
        virsh undefine "${vm_name}" --remove-all-storage 2>/dev/null || \
            virsh undefine "${vm_name}" 2>/dev/null || true
    fi

    # Remove working directory if it exists
    if [[ -d "${work_dir}" ]]; then
        log_info "Removing working directory: ${work_dir}"
        rm -rf "${work_dir}"
    fi

    log_info "VM '${vm_name}' has been completely removed"
}

# Set up working directory
WORK_DIR="/var/lib/libvirt/images/${VM_NAME}"
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/${UBUNTU_CODENAME}/current/${UBUNTU_CODENAME}-server-cloudimg-amd64.img"
CLOUD_IMAGE="${WORK_DIR}/${UBUNTU_CODENAME}-server-cloudimg-amd64.img"
VM_DISK="${WORK_DIR}/${VM_NAME}.qcow2"
CLOUD_INIT_ISO="${WORK_DIR}/cloud-init.iso"

setup_working_directory() {
    log_info "Setting up working directory: ${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
}

download_cloud_image() {
    if [[ -f "${CLOUD_IMAGE}" ]]; then
        log_info "Cloud image already exists, skipping download"
    else
        log_info "Downloading Ubuntu ${UBUNTU_VERSION} cloud image..."
        wget -q --show-progress -O "${CLOUD_IMAGE}" "${CLOUD_IMAGE_URL}"
    fi
}

create_vm_disk() {
    log_info "Creating VM disk (${DISK}GB)..."
    cp "${CLOUD_IMAGE}" "${VM_DISK}"
    qemu-img resize "${VM_DISK}" "${DISK}G"
}

# Generate hashed password
generate_password_hash() {
    echo "${PASSWORD}" | openssl passwd -6 -stdin
}

create_cloud_init_config() {
    log_info "Creating cloud-init configuration..."

    local PASSWORD_HASH
    PASSWORD_HASH=$(generate_password_hash)

    # Create user-data
    cat > "${WORK_DIR}/user-data" << EOF
#cloud-config
hostname: ${HOSTNAME}
manage_etc_hosts: true
users:
  - name: ${USERNAME}
    gecos: ${FULLNAME}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, docker, sudo
    home: /home/${USERNAME}
    shell: /bin/bash
    lock_passwd: false
    passwd: ${PASSWORD_HASH}
    ssh_pwauth: true

chpasswd:
  expire: false

ssh_pwauth: true

package_update: true
package_upgrade: true

packages:
  - ${DESKTOP}
  - xrdp
  - gnome-tweaks
  - curl
  - wget
  - git
  - build-essential
  - apt-transport-https
  - ca-certificates
  - gnupg
  - lsb-release
  - software-properties-common

write_files:
  - path: /opt/setup-desktop.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e

      export DEBIAN_FRONTEND=noninteractive

      echo "=== Installing Google Chrome ==="
      wget -q -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
      apt-get install -y /tmp/google-chrome.deb || apt-get install -f -y
      rm /tmp/google-chrome.deb

      echo "=== Installing Docker ==="
      curl -fsSL https://get.docker.com | sh
      usermod -aG docker ${USERNAME}
      systemctl enable docker
      systemctl start docker

      echo "=== Installing Tailscale ==="
      curl -fsSL https://tailscale.com/install.sh | sh

      echo "=== Installing Node.js LTS ==="
      curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
      apt-get install -y nodejs

      echo "=== Installing VS Code ==="
      wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
      install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
      echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
      apt-get update
      apt-get install -y code
      rm /tmp/packages.microsoft.gpg

      echo "=== Installing OpenClaw ==="
      npm install -g openclaw || npm install -g @anthropic-ai/claude-code || echo "OpenClaw/Claude Code installation attempted"

      echo "=== Configuring XRDP ==="
      systemctl enable xrdp
      systemctl start xrdp

      # Configure XRDP to use the desktop environment
      echo "gnome-session" > /home/${USERNAME}/.xsession
      chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.xsession

      # Allow colord for all users (fixes XRDP color profile issues)
      cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla << 'POLKIT'
      [Allow Colord all Users]
      Identity=unix-user:*
      Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
      ResultAny=no
      ResultInactive=no
      ResultActive=yes
      POLKIT

      echo "=== Setup Complete ==="

runcmd:
  - systemctl set-default graphical.target
  - /opt/setup-desktop.sh
  - reboot

final_message: "Ubuntu Desktop VM is ready! Connect via RDP or console."
EOF

    # Create meta-data
    cat > "${WORK_DIR}/meta-data" << EOF
instance-id: ${VM_NAME}
local-hostname: ${HOSTNAME}
EOF

    # Create network-config for DHCP
    cat > "${WORK_DIR}/network-config" << EOF
version: 2
ethernets:
  enp1s0:
    dhcp4: true
EOF

    # Generate cloud-init ISO
    log_info "Generating cloud-init ISO..."
    cloud-localds -v --network-config="${WORK_DIR}/network-config" \
        "${CLOUD_INIT_ISO}" \
        "${WORK_DIR}/user-data" \
        "${WORK_DIR}/meta-data"
}

create_vm() {
    log_info "Creating virtual machine: ${VM_NAME}"

    # Check if VM already exists
    if virsh dominfo "${VM_NAME}" &> /dev/null; then
        log_warn "VM '${VM_NAME}' already exists. Removing..."
        virsh destroy "${VM_NAME}" 2>/dev/null || true
        virsh undefine "${VM_NAME}" --remove-all-storage 2>/dev/null || true
    fi

    # Determine network configuration
    local network_opt
    if [[ -n "${BRIDGE}" ]]; then
        network_opt="bridge=${BRIDGE},model=virtio"
        log_info "Using bridge network: ${BRIDGE}"
    else
        network_opt="network=default,model=virtio"
        log_info "Using default NAT network"
    fi

    virt-install \
        --name "${VM_NAME}" \
        --ram "${RAM}" \
        --vcpus "${VCPUS}" \
        --disk path="${VM_DISK}",format=qcow2 \
        --disk path="${CLOUD_INIT_ISO}",device=cdrom \
        --os-variant ubuntu24.04 \
        --network "${network_opt}" \
        --graphics spice \
        --video qxl \
        --channel spicevmc \
        --console pty,target_type=serial \
        --noautoconsole \
        --import

    log_info "VM '${VM_NAME}' created and starting..."
}

print_summary() {
    # Get VM IP (may take a moment to appear)
    log_info "Waiting for VM to get an IP address..."
    local attempts=0
    local max_attempts=60
    local vm_ip=""

    while [[ $attempts -lt $max_attempts ]]; do
        vm_ip=$(virsh domifaddr "${VM_NAME}" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
        if [[ -n "${vm_ip}" ]]; then
            break
        fi
        sleep 5
        ((attempts++))
        echo -n "."
    done
    echo ""

    cat << EOF

${GREEN}============================================${NC}
${GREEN}   VM Installation Complete!${NC}
${GREEN}============================================${NC}

VM Name:        ${VM_NAME}
Hostname:       ${HOSTNAME}
Username:       ${USERNAME}
Full Name:      ${FULLNAME}
vCPUs:          ${VCPUS}
RAM:            ${RAM} MB
Disk:           ${DISK} GB
Desktop:        ${DESKTOP}
Network:        ${BRIDGE:-default (NAT)}
EOF

    if [[ -n "${vm_ip}" ]]; then
        cat << EOF
IP Address:     ${vm_ip}

Connect via RDP:
    rdesktop ${vm_ip}
    or
    xfreerdp /v:${vm_ip} /u:${USERNAME}
EOF
    else
        cat << EOF
IP Address:     (still acquiring, check with: virsh domifaddr ${VM_NAME})
EOF
    fi

    cat << EOF

Connect via Console:
    virsh console ${VM_NAME}

Connect via virt-viewer:
    virt-viewer ${VM_NAME}

Manage VM:
    virsh start ${VM_NAME}
    virsh shutdown ${VM_NAME}
    virsh destroy ${VM_NAME}

${YELLOW}Note: The first boot may take 10-20 minutes to complete
cloud-init setup and install all packages.${NC}

EOF
}

prompt_console_connect() {
    echo ""
    read -r -p "Would you like to connect to the VM console now? [y/N] " response
    case "${response}" in
        [yY][eE][sS]|[yY])
            log_info "Connecting to console (press Ctrl+] to exit)..."
            virsh console "${VM_NAME}"
            ;;
        *)
            log_info "You can connect later with: virsh console ${VM_NAME}"
            ;;
    esac
}

# Main execution
main() {
    log_info "Starting Ubuntu Cloud Image Desktop VM Installer v${VERSION}"

    # Handle remove mode
    if [[ "${REMOVE_VM}" == true ]]; then
        remove_vm "${VM_NAME}"
        exit 0
    fi

    log_info "VM Configuration:"
    log_info "  Hostname: ${HOSTNAME}"
    log_info "  Username: ${USERNAME}"
    log_info "  Full Name: ${FULLNAME}"
    log_info "  vCPUs: ${VCPUS}"
    log_info "  RAM: ${RAM} MB"
    log_info "  Disk: ${DISK} GB"
    log_info "  VM Name: ${VM_NAME}"
    log_info "  Desktop: ${DESKTOP}"
    log_info "  Network: ${BRIDGE:-default (NAT)}"

    check_dependencies
    setup_working_directory
    download_cloud_image
    create_vm_disk
    create_cloud_init_config
    create_vm
    print_summary
    prompt_console_connect
}

main
