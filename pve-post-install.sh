#!/usr/bin/env bash
# NDG Proxmox Post Install (PVE 8 and 9 compatible)

# CHANGELOG
# v0.4 - Added Registered Tags and Tag Style Color Map to Cluster Options
# v0.5 - Added More Registered Tags and Tag Style Overrides
# v0.6 - Install Prometheus Node Exporter
# v0.7 - Support PVE 9.x (Debian 13 "trixie"), dynamic repo setup, robust version check

VER="0.7"

RD=$(echo "\033[01;31m")
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
BL=$(echo "\033[0;34m")
LBL=$(echo "\033[1;34m")

BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

set -euo pipefail
shopt -s inherit_errexit nullglob

msg_info() { echo -ne " ${HOLD} ${YW}${1}..."; }
msg_ok()   { echo -e "${BFR} ${CM} ${GN}${1}${CL}"; }
msg_error(){ echo -e "${BFR} ${CROSS} ${RD}${1}${CL}"; }

header_info() {
  clear
  TXT=$(cat <<"EOF"
  \033[1;34m        \033[m __   __ _____   _____  
  \033[1;34m       _\033[m|  \ |  |  __ \ / ____\ 
  \033[1;34m     _| \033[m|   \|  | |  | | |  __ 
  \033[1;34m   _| | \033[m|  . `  | |  | | | |_ |
  \033[1;34m _| | | \033[m|  |\   | |__| | |__| |
  \033[1;34m|_|_|_|_\033[m|__| \__|_____/ \_____|
                                                 
EOF
)
  echo -e "${TXT}"
  echo -e "  \033[1;34mProxmox Post Install version v${VER}\033[m"
}

get_codename() {
  . /etc/os-release
  # VERSION_CODENAME is 'bookworm' on PVE8, 'trixie' on PVE9
  echo "${VERSION_CODENAME}"
}

correct_sources() {
  msg_info "Correcting Debian sources (main/contrib/non-free-firmware)"
  local CODENAME; CODENAME="$(get_codename)"
  cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian ${CODENAME} main contrib non-free-firmware
deb http://deb.debian.org/debian ${CODENAME}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${CODENAME}-security main contrib non-free-firmware
EOF
  msg_ok "Corrected Debian sources (${CODENAME})"
}

correct_ceph() {
  # Keep Ceph repos disabled but present, matching both PVE8/9 eras
  msg_info "Correcting 'ceph package repositories' (disabled placeholders)"
  local CODENAME; CODENAME="$(get_codename)"
  cat >/etc/apt/sources.list.d/ceph.list <<EOF
# Examples (disabled):
# deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
# deb http://download.proxmox.com/debian/ceph-reef   bookworm no-subscription
# deb http://download.proxmox.com/debian/ceph-squid  trixie   no-subscription
EOF
  msg_ok "Corrected 'ceph package repositories'"
}

disable_enterprise() {
  msg_info "Disabling 'pve-enterprise' repository"
  # Legacy .list
  echo '# disabled' >/etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
  # deb822 .sources (PVE 8/9 default)
  if [ -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then
    sed -i 's/^\(Types:\|URIs:\|Suites:\|Components:\)/# \1/' /etc/apt/sources.list.d/pve-enterprise.sources || true
  fi
  msg_ok "Disabled 'pve-enterprise' repository"
}

no_subscription() {
  msg_info "Enabling 'pve-no-subscription' repository (deb822)"
  local CODENAME; CODENAME="$(get_codename)"
  # Ensure keyring exists (normally present on PVE)
  apt-get update &>/dev/null || true
  apt-get -y install proxmox-archive-keyring &>/dev/null || true

  cat >/etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: ${CODENAME}
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  msg_ok "Enabled 'pve-no-subscription' (${CODENAME})"
}

remove_local_lvm() {
  msg_info "Reclaiming disk space on local (remove local-lvm if present)"
  {
    pvesm remove local-lvm &>/dev/null
    yes | lvremove /dev/pve/data &>/dev/null
    lvresize -l +100%FREE /dev/pve/root &>/dev/null
    resize2fs /dev/mapper/pve-root &>/dev/null
  } || {
    msg_info "Datastore local-lvm not present... skipping"
  }
  msg_ok "Local-lvm processed"
}

disable_ha() {
  msg_info "Disabling high availability services"
  systemctl disable -q --now pve-ha-lrm || true
  systemctl disable -q --now pve-ha-crm || true
  msg_ok "Disabled high availability"
}

tag_color_map() {
  msg_info "Registering NDG VMDIST tags"
  pvesh set /cluster/options --registered-tags='vmdist.cisco;vmdist.cisco_cml;vmdist.cisco_pt;vmdist.cssia;vmdist.emc;vmdist.lpi;vmdist.ndg_genit;vmdist.ndg_hosted;vmdist.netlab;vmdist.nisgtc_gis;vmdist.paloalto;vmdist.redhat;vmdist.ring;vmdist.vmware;windows;full;link;nrml;tmpl;mstr;prst;stag'
  pvesh set /cluster/options --tag-style='color-map=vmdist.cisco:16A085:FFFFFF;vmdist.cisco_cml:16A085:FFFFFF;vmdist.cisco_pt:16A085:FFFFFF;vmdist.cssia:16A085:FFFFFF;vmdist.emc:16A085:FFFFFF;vmdist.lpi:16A085:FFFFFF;vmdist.ndg_genit:16A085:FFFFFF;vmdist.ndg_hosted:16A085:FFFFFF;vmdist.netlab:16A085:FFFFFF;vmdist.nisgtc_gis:16A085:FFFFFF;vmdist.paloalto:16A085:FFFFFF;vmdist.redhat:16A085:FFFFFF;vmdist.ring:16A085:FFFFFF;vmdist.vmware:16A085:FFFFFF;windows:FDD835:000000;nrml:3498DB:FFFFFF;mstr:F48FB1:000000;tmpl:9B59B6:FFFFFF;full:666666:FFFFFF;link:DDDDDD:000000;prst:F39C12:000000;stag:EC407A:FFFFFF'
  msg_ok "Registered NDG VMDIST tags"
}

setup_node_exporter() {
  msg_info "Configuring Prometheus Node Exporter on port 9100"
  apt-get update &>/dev/null
  apt-get -y install prometheus-node-exporter &>/dev/null
  systemctl enable --now prometheus-node-exporter &>/dev/null || true
  msg_ok "Prometheus Node Exporter ready"
}

update_pve() {
  msg_info "Updating Proxmox VE (this can take a while)"
  apt-get update &>/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade &>/dev/null
  msg_ok "Updated Proxmox VE"
}

reboot_now() {
  local choice="no"
  if command -v whiptail >/dev/null 2>&1; then
    local ch
    ch=$(whiptail --backtitle "NDG PVE Post Install" --title "REBOOT" --menu "\nReboot this Proxmox VE server now? (recommended)" 11 58 2 \
      "yes" " " \
      "no" " " 3>&2 2>&1 1>&3) || ch="no"
    choice="${ch}"
  else
    read -r -p "Reboot this Proxmox VE server now? [y/N]: " ch
    case "${ch:-N}" in [Yy]*) choice="yes" ;; *) choice="no" ;; esac
  fi

  case "${choice}" in
    yes)
      msg_info "Rebooting Proxmox VE"
      sleep 2
      msg_ok "Completed Post Install. Server is ready for NETLAB+"
      reboot
      ;;
    *)
      msg_error "Selected no to rebooting Proxmox VE (reboot recommended)"
      msg_ok "Completed Post Install. Please reboot as soon as possible."
      ;;
  esac
}

start_routines() {
  correct_sources
  correct_ceph
  disable_enterprise
  no_subscription
  remove_local_lvm
  disable_ha
  tag_color_map
  setup_node_exporter
  update_pve
  reboot_now
}

require_min_version() {
  # Require PVE >= 8.0 (accepts 8.x and 9.x)
  local PVE_VER RAW
  RAW="$(pveversion || true)"
  PVE_VER="$(sed -n 's/^pve-manager\/\([0-9][0-9]*\(\.[0-9][0-9]*\)\{0,2\}\).*/\1/p' <<<"$RAW")"
  if [ -z "${PVE_VER}" ]; then
    msg_error "Unable to detect Proxmox VE version from: $RAW"
    echo -e "Exiting..."
    exit 1
  fi
  if dpkg --compare-versions "$PVE_VER" lt "8.0"; then
    msg_error "This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 8.0 or later."
    echo -e "Detected: $PVE_VER"
    sleep 2
    exit 1
  fi
}

header_info
echo -e "\nThis script will modify this system for use with ${LBL}NDG NETLAB+${CL}.\n"

while true; do
  read -r -p "Are you sure you want to proceed (y/n)? " yn
  case "$yn" in
    [Yy]*) break ;;
    [Nn]*) clear; exit ;;
    *) echo "Please answer yes or no." ;;
  esac
done

require_min_version

mkdir -p /etc/ndg
echo "$(date)   $VER" >> /etc/ndg/post-install.log

start_routines
