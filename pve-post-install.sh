#!/usr/bin/env bash

# CHANGELOG
# v0.4 - Added Registered Tags and Tag Style Color Map to Cluster Options
# v0.5 - Added More Registered Tags and Tag Style Overrides
# v0.6 - Install Prometheus Node Exporter

VER="0.6"

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

msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}


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

correct_sources() {
    msg_info "Correcting Proxmox VE Sources"
    cat <<EOF >/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
EOF
    echo 'APT::Get::Update::SourceListWarnings::NonFreeFirmware "false";' >/etc/apt/apt.conf.d/no-bookworm-firmware.conf
    msg_ok "Corrected Proxmox VE Sources"
}

correct_ceph() {
    msg_info "Correcting 'ceph package repositories'"
    cat <<EOF >/etc/apt/sources.list.d/ceph.list
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
# deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
# deb https://enterprise.proxmox.com/debian/ceph-reef bookworm enterprise
# deb http://download.proxmox.com/debian/ceph-reef bookworm no-subscription
EOF
    msg_ok "Corrected 'ceph package repositories'"
}

disable_enterprise() {
    msg_info "Disabling 'pve-enterprise' repository"
    cat <<EOF >/etc/apt/sources.list.d/pve-enterprise.list
# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise
EOF
    msg_ok "Disabled 'pve-enterprise' repository"
}

no_subscription() {
    msg_info "Enabling 'pve-no-subscription' repository"
    cat <<EOF >/etc/apt/sources.list.d/pve-install-repo.list
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF
    msg_ok "Enabled 'pve-no-subscription' repository"
}

remove_local_lvm() {
  msg_info "Reclaiming disk space on local"
  
  { # try

    pvesm remove local-lvm &>/dev/null
    yes | lvremove /dev/pve/data &>/dev/null
    lvresize -l +100%FREE /dev/pve/root &>/dev/null
    resize2fs /dev/mapper/pve-root &>/dev/null

  } || { # catch
    msg_info "Datastore local-lvm not present... skipping"
  }
  
  msg_ok "Removed local-lvm"
}

disable_ha() {
  msg_info "Disabling high availability"
  systemctl disable -q --now pve-ha-lrm
  systemctl disable -q --now pve-ha-crm
  msg_ok "Disabled high availability"
}

tag_color_map() {
  msg_info "Registering NDG VMDIST tags"

  pvesh set /cluster/options --registered-tags='vmdist.cisco;vmdist.cisco_cml;vmdist.cisco_pt;vmdist.cssia;vmdist.emc;vmdist.lpi;vmdist.ndg_genit;vmdist.ndg_hosted;vmdist.netlab;vmdist.nisgtc_gis;vmdist.paloalto;vmdist.redhat;vmdist.ring;vmdist.vmware;windows;full;link;nrml;tmpl;mstr;prst;stag'

  pvesh set /cluster/options --tag-style='color-map=vmdist.cisco:16A085:FFFFFF;vmdist.cisco_cml:16A085:FFFFFF;vmdist.cisco_pt:16A085:FFFFFF;vmdist.cssia:16A085:FFFFFF;vmdist.emc:16A085:FFFFFF;vmdist.lpi:16A085:FFFFFF;vmdist.ndg_genit:16A085:FFFFFF;vmdist.ndg_hosted:16A085:FFFFFF;vmdist.netlab:16A085:FFFFFF;vmdist.nisgtc_gis:16A085:FFFFFF;vmdist.paloalto:16A085:FFFFFF;vmdist.redhat:16A085:FFFFFF;vmdist.ring:16A085:FFFFFF;vmdist.vmware:16A085:FFFFFF;windows:FDD835:000000;nrml:3498DB:FFFFFF;mstr:F48FB1:000000;tmpl:9B59B6:FFFFFF;full:666666:FFFFFF;link:DDDDDD:000000;prst:F39C12:000000;stag:EC407A:FFFFFF'
  
  msg_ok "Registered NDG VMDIST tags"
}

setup_node_exporter() {
  msg_info "Configuring Prometheus Metrics on port 9100"

  apt-get update &>/dev/null
  apt-get -y install prometheus-node-exporter &>/dev/null
  
  msg_ok "Configured Prometheus Metrics on port 9100"
}

update_pve() {
  msg_info "Updating Proxmox VE (please be patient)"
  apt-get update &>/dev/null
  apt-get -y dist-upgrade &>/dev/null
  msg_ok "Updated Proxmox VE"
}

reboot_now() {
  CHOICE=$(whiptail --backtitle "NDG PVE Post Install" --title "REBOOT" --menu "\nReboot this Proxmox VE server now? (recommended)" 11 58 2 \
    "yes" " " \
    "no" " " 3>&2 2>&1 1>&3)
  case $CHOICE in
  yes)
    msg_info "Rebooting Proxmox VE"
    sleep 2
    msg_ok "Completed Post Install. Server is ready for NETLAB+"
    reboot
    ;;
  no)
    msg_error "Selected no to rebooting Proxmox VE (reboot recommended)"
    msg_ok "Completed Post Install. Please reboot as soon as possible. "
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

header_info
echo -e "\nThis script will modify this system for use with ${LBL}NDG NETLAB+${CL}.\n"
while true; do
  read -p "Are you sure you want to proceed (y/n)? " yn
  case $yn in
  [Yy]*) break ;;
  [Nn]*)
    clear
    exit
    ;;
  *) echo "Please answer yes or no. " ;;
  esac
done

# require >= 8.0
PVE_VER="$(pveversion | sed -n 's/^pve-manager\/\([0-9][^/]*\).*/\1/p')"
if dpkg --compare-versions "$PVE_VER" lt "8.0"; then
  msg_error "This version of Proxmox Virtual Environment is not supported"
  echo -e "Requires Proxmox Virtual Environment Version 8.0 or later."
  echo -e "Exiting..."
  sleep 2
  exit
fi

mkdir -p /etc/ndg
echo "$(date)   $VER" >> /etc/ndg/post-install.log

start_routines
