#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1
# this installs a package from fedora repos
dnf5 install -y \
# TODO: Remember to add more langpacks (or all)
    glibc-langpack-en \
    glibc-langpack-pt \
    tmux \
    cinnamon \
    cinnamon-control-center \
    firefox \
    gnome-terminal \
    slick-greeter \
    slick-greeter-cinnamon \
    nemo-fileroller \
    nemo-image-converter \
    nemo-preview \
    xed \
    xreader \
    eom \
    gvfs-mtp \
    gvfs-smb \
    NetworkManager-wifi \
    NetworkManager-bluetooth \
    nm-connection-editor \
    pipewire-alsa \
    pipewire-pulseaudio \
    wireplumber \
    xdg-user-dirs-gtk \
    qt6-qtwayland-adwaita-decoration \
    paper-icon-theme
    
# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket
