# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base Image
FROM quay.io/fedora/fedora-bootc:44
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:testing
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

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
    vim-minimal

RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    mkdir -p /var/roothome && \
    dnf5 -y install \
        dnf5-plugins \
        fedora-repos-archive \
        zstd && \
    dnf5 -y swap --repo=fedora \
        OpenCL-ICD-Loader ocl-icd && \
    dnf5 -y copr enable ublue-os/packages && \
    dnf5 -y copr enable ublue-os/staging && \
    dnf5 -y install \
        ublue-os-just \
        ublue-os-luks \
        ublue-os-signing \
        ublue-os-udev-rules \
        ublue-os-update-services && \
    if ! grep -q fedora-multimedia < <(dnf5 repolist); then \
        dnf5 config-manager setopt fedora-multimedia.enabled=1 || \
        dnf5 config-manager addrepo \
            --from-repofile=https://negativo17.org/repos/fedora-multimedia.repo; \
    fi && \
    dnf5 config-manager setopt fedora-multimedia.priority=90

# Setup Copr repos
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/log \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    mkdir -p /var/roothome && \
    dnf5 config-manager setopt keepcache=1 && \
    for copr in \
        ublue-os/bazzite \
        ublue-os/bazzite-multilib \
        ublue-os/staging \
        ublue-os/packages \
        ycollet/audinux \
        che/nerd-fonts; \
    do \
        echo "Enabling copr: $copr"; \
        dnf5 -y copr enable $copr; \
        dnf5 -y config-manager setopt copr:copr.fedorainfracloud.org:${copr////:}.priority=98 ;\
    done && unset -v copr && \
    dnf5 -y install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release{,-extras,-mesa} && \
    dnf5 -y config-manager addrepo --overwrite --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo && \
    sed -i 's@enabled=0@enabled=1@g' /etc/yum.repos.d/negativo17-fedora-multimedia.repo && \
    dnf5 -y config-manager setopt "*terra*".priority=1 "*terra*".exclude="nerd-fonts scx-tools scx-scheds python3-protobuf zlib-devel uupd" && \
    dnf5 -y config-manager setopt "terra-mesa".enabled=false && \
    dnf5 -y config-manager setopt "*bazzite*".priority=2 && \
    eval "$(/ctx/dnf5-setopt setopt '*negativo17*' priority=4 exclude='mesa-* *xone*')" && \
    dnf5 -y config-manager setopt "*fedora*".exclude="mesa-* kernel-core-* kernel-modules-* kernel-uki-virt-* steam" && \
    dnf5 -y config-manager setopt "*audinux*".exclude="kernel*" && \
    dnf5 -y config-manager setopt "*staging*".exclude="scx-tools scx-scheds kf6-* mesa* mutter*" && \
    /ctx/cleanup

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
