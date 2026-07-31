# Temporary build context.
# Files copied here are available only during image construction and are not
# included in the final image unless explicitly copied elsewhere.
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files


# Base immutable operating system image.
# Fedora bootc provides the minimal bootable container foundation:
# systemd, rpm, rpm-ostree/bootc integration, SELinux policy, and Fedora userspace.
FROM quay.io/fedora/fedora-bootc:44


# Install the basic userspace expected from a desktop-oriented bootc image.
#
# dnf5-plugins:
#   Provides additional dnf5 commands such as config-manager and copr.
#
# NetworkManager/systemd-resolved:
#   Required for normal desktop networking.
#
# firewalld/fwupd:
#   Firewall management and firmware update support.
#
# zram-generator-defaults:
#   Enables compressed RAM swap by default.
#
# plymouth:
#   Boot splash support.
#
# openssh:
#   Remote administration support.
#
# parted/e2fsprogs:
#   Disk and filesystem management tools.
#
# man-db/less/vim-minimal:
#   Basic administrative tools.
#
# fedora-repos-archive:
#   Provides archived Fedora repository definitions.
#
# zstd:
#   Compression utility commonly used by Fedora/bootc tooling.
RUN dnf5 install -y \
    dnf5-plugins \
    NetworkManager \
    systemd-resolved \
    firewalld \
    fwupd \
    zram-generator-defaults \
    plymouth \
    e2fsprogs \
    openssh-clients \
    openssh-server \
    parted \
    less \
    man-db \
    vim-minimal \
    fedora-repos-archive \
    zstd


# Install Universal Blue base components and configure additional repositories.
#
# This reproduces the common ublue-os/main preparation layer:
# - fixes Fedora OpenCL package naming mismatch
# - enables ublue COPR repositories
# - installs ublue system integration packages
# - enables Fedora Multimedia repository for additional codecs
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    mkdir -p /var/roothome && \
    \
    # Replace Fedora OpenCL ICD loader with the implementation expected by Fedora/ublue.
    dnf5 -y swap --repo=fedora \
        OpenCL-ICD-Loader ocl-icd && \
    \
    # Enable Universal Blue package repositories.
    dnf5 -y copr enable ublue-os/packages && \
    dnf5 -y copr enable ublue-os/staging && \
    \
    # Install Universal Blue integration packages.
    dnf5 -y install \
        ublue-os-just \
        ublue-os-luks \
        ublue-os-signing \
        ublue-os-udev-rules \
        ublue-os-update-services && \
    \
    # Enable Negativo17 Fedora Multimedia repository.
    # Used mainly for multimedia codecs and hardware acceleration packages.
    if ! dnf5 repolist | grep -q fedora-multimedia; then \
        dnf5 config-manager addrepo \
            --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo; \
    fi && \
    \
    dnf5 config-manager setopt \
        fedora-multimedia.priority=90


# Configure additional repositories used by Bazzite.
#
# COPR repositories:
#   ublue-os/bazzite:
#       Bazzite-specific packages.
#
#   ublue-os/bazzite-multilib:
#       32-bit libraries required by gaming software.
#
#   ycollet/audinux:
#       Audio production packages.
#
#   che/nerd-fonts:
#       Nerd Fonts packages.
#
# Terra:
#   Third-party Fedora-compatible repository maintained by Fyra Labs.
#
# Tailscale:
#   Official repository for the Tailscale VPN client.
#
# Repository priorities are adjusted to avoid Fedora packages replacing
# specialized versions from Bazzite/Terra repositories.
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    mkdir -p /var/roothome && \
    \
    dnf5 config-manager setopt keepcache=1 && \
    \
    for copr in \
        ublue-os/bazzite \
        ublue-os/bazzite-multilib \
        ycollet/audinux \
        che/nerd-fonts; do \
            echo "Enabling COPR: ${copr}"; \
            dnf5 -y copr enable "$copr"; \
            dnf5 -y config-manager setopt \
                "copr:copr.fedorainfracloud.org:${copr////:}.priority=98"; \
    done && \
    \
    # Install Terra repository definitions.
    dnf5 -y install \
        --nogpgcheck \
        --repofrompath='terra,https://repos.fyralabs.com/terra$releasever' \
        terra-release \
        terra-release-extras \
        terra-release-mesa && \
    \
    # Add Tailscale repository.
    dnf5 -y config-manager addrepo \
        --overwrite \
        --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo && \
    \
    # Prefer Terra packages except where Fedora/Bazzite packages are required.
    dnf5 config-manager setopt \
        "*terra*".priority=1 \
        "*terra*".exclude="nerd-fonts scx-tools scx-scheds python3-protobuf zlib-devel uupd" && \
    \
    # Disable Terra Mesa because GPU drivers are handled elsewhere.
    dnf5 config-manager setopt \
        terra-mesa.enabled=false && \
    \
    # Prefer Bazzite COPR over Fedora packages.
    dnf5 config-manager setopt \
        "*bazzite*".priority=2 && \
    \
    # Prevent Fedora from replacing critical packages maintained by Bazzite.
    dnf5 config-manager setopt \
        "*fedora*".exclude="mesa-* kernel-core-* kernel-modules-* kernel-uki-virt-* steam" && \
    \
    # Avoid pulling incompatible kernel packages from Audinux.
    dnf5 config-manager setopt \
        "*audinux*".exclude="kernel*"


# Run user customization scripts.
# This is where additional packages, services, configuration files,
# and image-specific modifications should be applied.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN dnf5 install -y flatpak flatseal bazaar distrobox

# Clean image before bootc lint
RUN \
    # Remove temporary files
    rm -rf /tmp/* && \
    rm -rf /run/* && \
    \
    # Remove logs
    rm -f /var/log/dnf5.log && \
    find /var/log -type f -delete && \
    \
    # bootc does not allow /usr/etc
    rm -rf /usr/etc && \
    \
    # Remove boot contents
    rm -rf /boot/* && \
    \
    # Remove DNF state
    rm -rf /var/lib/dnf && \
    rm -rf /var/cache/dnf && \
    rm -rf /var/cache/libdnf5 && \
    \
    # Recreate expected directories
    mkdir -p /var/cache/libdnf5 && \
    mkdir -p /var/tmp && \
    chmod 1777 /var/tmp

# Validate that the generated image follows bootc requirements.
RUN bootc container lint
