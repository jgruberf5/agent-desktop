# Ubuntu Cloud Image Desktop VM Installer

A bash script to quickly deploy Ubuntu Desktop virtual machines on KVM/libvirt hosts using cloud images and cloud-init.

## Features

- Deploys Ubuntu 24.04 (Noble) Desktop VMs from official cloud images
- Cloud-init based configuration for reproducible deployments
- XRDP enabled for remote desktop access
- SPICE graphics for local console access
- Automatic installation of development tools:
  - Google Chrome
  - Docker
  - Tailscale
  - Node.js (latest LTS)
  - VS Code
  - OpenClaw

## Requirements

- Linux host with KVM support
- AMD64 architecture
- Root/sudo privileges
- The following packages (installed automatically if missing):
  - `qemu-kvm`
  - `libvirt-daemon-system`
  - `libvirt-clients`
  - `virtinst`
  - `cloud-image-utils`
  - `wget`

## Quick Start

### Install from GitHub Release

Run directly from the latest release:

```bash
curl -fsSL https://github.com/OWNER/REPO/releases/latest/download/install.sh | sudo bash -s -- \
  --hostname mydesktop \
  --username myuser \
  --fullname "John Doe" \
  --password mypassword
```

### Download and Run

```bash
wget https://github.com/OWNER/REPO/releases/latest/download/install.sh
chmod +x install.sh
sudo ./install.sh --help
```

### Clone and Run

```bash
git clone https://github.com/OWNER/REPO.git
cd REPO
sudo ./install.sh \
  --hostname mydesktop \
  --username myuser \
  --fullname "John Doe" \
  --password mypassword
```

## Usage

```
Ubuntu Cloud Image Desktop VM Installer for KVM v1.0.0

Usage: ./install.sh [OPTIONS]

Options:
    -h, --hostname      VM hostname (default: ubuntu-desktop)
    -u, --username      Username for the VM (default: user)
    -f, --fullname      Full name of the user (default: Ubuntu User)
    -p, --password      User password (required for install)
    -c, --vcpus         Number of vCPUs (default: 4)
    -r, --ram           RAM size in MB (default: 8192)
    -d, --disk          Disk size in GB (default: 50)
    -n, --name          Virtual machine name (default: ubuntu-desktop-vm)
    -e, --desktop       Desktop environment package (default: ubuntu-desktop-minimal)
    -b, --bridge        Host bridge for VM network (e.g., br0)
    -D, --hostdev       Host device passthrough (repeatable)
    -s, --silent        Silent install (no output, no prompts)
    --remove            Remove the VM and all associated storage
    --help              Show this help message
    --version           Show version
```

## Examples

### Basic Installation

```bash
sudo ./install.sh -p mypassword
```

### Full Custom Configuration

```bash
sudo ./install.sh \
  --hostname dev-workstation \
  --username developer \
  --fullname "Jane Developer" \
  --password secretpass \
  --vcpus 8 \
  --ram 16384 \
  --disk 200 \
  --name dev-vm \
  --desktop ubuntu-desktop
```

### Using Short Options

```bash
sudo ./install.sh -h devbox -u dev -f "Dev User" -p pass123 -c 4 -r 8192 -d 100 -n my-vm
```

### Using a Host Bridge

Connect the VM directly to your network using a host bridge:

```bash
sudo ./install.sh \
  --hostname bridged-vm \
  --username myuser \
  --password mypassword \
  --bridge br0
```

### Removing a VM

Completely remove a VM and all associated storage:

```bash
sudo ./install.sh --remove --name my-vm
```

### GPU/Device Passthrough

Pass through PCI or USB devices to the VM using the repeatable `--hostdev` option:

```bash
# Find available devices
virsh nodedev-list

# Pass through a GPU (and its audio device)
sudo ./install.sh \
  --hostname gpu-vm \
  --username myuser \
  --password mypassword \
  --hostdev pci_0000_01_00_0 \
  --hostdev pci_0000_01_00_1

# Pass through a USB device
sudo ./install.sh \
  --password mypassword \
  --hostdev usb_1d6b_0002
```

### Silent Installation

Run without output or prompts (useful for automation):

```bash
sudo ./install.sh \
  --silent \
  --hostname auto-vm \
  --username myuser \
  --password mypassword \
  --name automated-vm
```

## Desktop Environments

You can install different Ubuntu desktop flavors using the `--desktop` option:

| Package | Desktop Environment |
|---------|---------------------|
| `ubuntu-desktop` | GNOME (default) |
| `ubuntu-desktop-minimal` | GNOME (minimal) |
| `kubuntu-desktop` | KDE Plasma |
| `xubuntu-desktop` | XFCE |
| `lubuntu-desktop` | LXQt |
| `ubuntu-mate-desktop` | MATE |
| `ubuntu-budgie-desktop` | Budgie |
| `ubuntucinnamon-desktop` | Cinnamon |

### Example: KDE Plasma Desktop

```bash
sudo ./install.sh \
  --hostname kde-desktop \
  --username myuser \
  --password mypassword \
  --desktop kubuntu-desktop
```

## Connecting to the VM

### Remote Desktop (RDP)

Once the VM is running and cloud-init has completed setup:

```bash
# Using rdesktop
rdesktop <vm-ip-address>

# Using FreeRDP
xfreerdp /v:<vm-ip-address> /u:<username>

# Using FreeRDP with dynamic resolution
xfreerdp /v:<vm-ip-address> /u:<username> /dynamic-resolution
```

### SPICE Console

```bash
virt-viewer <vm-name>
```

### Serial Console

```bash
virsh console <vm-name>
```

## Managing the VM

### Get VM IP Address

```bash
virsh domifaddr <vm-name>
```

### Start/Stop/Restart

```bash
# Start
virsh start <vm-name>

# Graceful shutdown
virsh shutdown <vm-name>

# Force stop
virsh destroy <vm-name>

# Restart
virsh reboot <vm-name>
```

### Delete VM

```bash
# Stop if running
virsh destroy <vm-name>

# Remove VM and storage
virsh undefine <vm-name> --remove-all-storage
```

### View VM Console

```bash
# Graphical console
virt-viewer <vm-name>

# Serial console
virsh console <vm-name>
```

## Cloud-Init Setup

The first boot performs the following operations via cloud-init:

1. Sets hostname and configures `/etc/hosts`
2. Creates user account with sudo privileges
3. Updates and upgrades system packages
4. Installs the selected desktop environment
5. Installs XRDP for remote desktop access
6. Runs the setup script to install:
   - Google Chrome
   - Docker (with user added to docker group)
   - Tailscale
   - Node.js LTS
   - VS Code
   - OpenClaw
7. Enables graphical target and reboots

The first boot typically takes 10-20 minutes depending on your internet connection and host performance.

## File Locations

| Path | Description |
|------|-------------|
| `/var/lib/libvirt/images/<vm-name>/` | VM working directory |
| `/var/lib/libvirt/images/<vm-name>/<vm-name>.qcow2` | VM disk image |
| `/var/lib/libvirt/images/<vm-name>/cloud-init.iso` | Cloud-init configuration |
| `/var/lib/libvirt/images/<vm-name>/user-data` | Cloud-init user-data |
| `/var/lib/libvirt/images/<vm-name>/meta-data` | Cloud-init meta-data |

## Troubleshooting

### VM Not Getting IP Address

Check if the default network is active:

```bash
virsh net-list --all
virsh net-start default
```

### Cloud-Init Not Running

Check cloud-init status inside the VM:

```bash
cloud-init status
cat /var/log/cloud-init-output.log
```

### XRDP Connection Issues

Verify XRDP is running inside the VM:

```bash
systemctl status xrdp
```

Check firewall rules:

```bash
sudo ufw status
sudo ufw allow 3389/tcp
```

### Desktop Not Loading via RDP

Check the `.xsession` file:

```bash
cat ~/.xsession
# Should contain: gnome-session (or appropriate session command)
```

## Development

### Creating a Release

Releases are automatically created when a new tag is pushed:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Actions workflow will:
1. Validate the script syntax
2. Run shellcheck
3. Update the version in the script
4. Create checksums
5. Publish the release with the install script

### Running Tests Locally

```bash
# Validate syntax
bash -n install.sh

# Run shellcheck
shellcheck install.sh

# Test help output
./install.sh --help
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
