# PI-CI
# Shared variables
ARG BUILD_DIR=/build/

FROM ubuntu:24.04 AS builder

# Use shared build directory
ARG BUILD_DIR

# Kernel source
ARG KERNEL_GIT=https://github.com/raspberrypi/linux.git
ARG KERNEL_BRANCH=rpi-6.6.y

# Distro download
ARG DISTRO_FILE=2024-07-04-raspios-bookworm-arm64-lite.img
ARG DISTRO_IMG=https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/$DISTRO_FILE.xz

# Kernel compile options
ARG ARCH=arm64
ARG CROSS_COMPILE=aarch64-linux-gnu-

# Install dependencies
ARG DEBIAN_FRONTEND="noninteractive"
RUN apt-get update && apt install -y \
    bc \
    bison \
    crossbuild-essential-arm64 \
    flex \
    git \
    libc6-dev \
    libguestfs-tools \
    libssl-dev \
    linux-image-generic \
    make \
    wget \
    openssl \
    xz-utils

# Download raspbian distro
RUN wget -nv -O /tmp/$DISTRO_FILE.xz $DISTRO_IMG \
 && unxz /tmp/$DISTRO_FILE.xz

# Extract distro boot and root
RUN mkdir /mnt/root /mnt/boot \
 && guestfish add tmp/$DISTRO_FILE : run : mount /dev/sda1 / : copy-out / /mnt/boot : umount / : mount /dev/sda2 / : copy-out / /mnt/root

# Clone the RPI kernel repo
RUN git clone --single-branch --branch $KERNEL_BRANCH $KERNEL_GIT $BUILD_DIR/linux/

# Insert kernel configuration
COPY src/conf/.config $BUILD_DIR/linux

# Cross compile vm kernel image
RUN make -C $BUILD_DIR/linux -j$(nproc) Image \
 && mv $BUILD_DIR/linux/arch/arm64/boot/Image $BUILD_DIR/kernel.img

# Copy boot configuration
COPY src/conf/fstab /mnt/root/etc/
COPY src/conf/cmdline.txt /mnt/boot/
COPY src/conf/99-qemu.rules /mnt/root/etc/udev/rules.d/

# Run SSH server on startup
RUN touch /mnt/boot/ssh

# Allow SSH root login with no password
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /mnt/root/etc/ssh/sshd_config \
 && sed -i 's/#PermitEmptyPasswords no/permitEmptyPasswords yes/' /mnt/root/etc/ssh/sshd_config

# Enable root login and remove user 'pi'
RUN sed -i 's/^root:\*:/root::/' /mnt/root/etc/shadow \
 && sed -i '/^pi/d' /mnt/root/etc/shadow \
 && sed -i '/^pi/d' /mnt/root/etc/passwd \
 && sed -i '/^pi/d' /mnt/root/etc/group \
 && rm -r /mnt/root/home/pi

# Setup root auto login
RUN mkdir /mnt/root/etc/systemd/system/serial-getty@ttyAMA0.service.d/
COPY src/conf/login.conf /mnt/root/etc/systemd/system/serial-getty@ttyAMA0.service.d/override.conf

# Disable userconfig.service
RUN rm /mnt/root/usr/lib/systemd/system/userconfig.service \
 && rm /mnt/root/etc/systemd/system/multi-user.target.wants/userconfig.service

# Create new distro image from modified boot and root
RUN guestfish -N $BUILD_DIR/distro.img=bootroot:vfat:ext4:2G \
 && guestfish add $BUILD_DIR/distro.img : run : mount /dev/sda1 / : glob copy-in /mnt/boot/* / : umount / : mount /dev/sda2 / : glob copy-in /mnt/root/* / \
 && sfdisk --part-type $BUILD_DIR/distro.img 1 c
# Convert new distro image to sparse file
RUN qemu-img convert -f raw -O qcow2 $BUILD_DIR/distro.img $BUILD_DIR/distro.qcow2

CMD cp $BUILD_DIR/distro.qcow2 ./


# ---------------------------
FROM ubuntu:24.04 AS emulator

# Project build directory
ARG BUILD_DIR
# Folder containing default configuration files
ENV BASE_DIR=/base/
# Folder containing helper scripts
ENV APP_DIR=/app/

ENV IMAGE_FILE_NAME=distro.qcow2
ENV KERNEL_FILE_NAME=kernel.img

# Copy build files
RUN mkdir $BASE_DIR
COPY --from=0 $BUILD_DIR/$IMAGE_FILE_NAME $BASE_DIR/$IMAGE_FILE_NAME
COPY --from=0 $BUILD_DIR/$KERNEL_FILE_NAME $BASE_DIR/$KERNEL_FILE_NAME

# Install packages and build essentials
ARG DEBIAN_FRONTEND="noninteractive"
RUN apt-get update && apt install -y \
    python3 \
    python3-pip \
    qemu-system-arm \
    linux-image-generic \
    libguestfs-tools \
    qemu-efi-aarch64

ENV PIP_BREAK_SYSTEM_PACKAGES 1

# Copy and install Python dependencies
COPY src/app/requirements.txt $APP_DIR/requirements.txt
RUN pip3 install -r $APP_DIR/requirements.txt

# Copy helper scripts
COPY src/app/ $APP_DIR

# Helper script on running container
ENTRYPOINT ["/app/run.py"]

# Helper variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV DIST_DIR /dist
ENV STORAGE_PATH /dev/mmcblk0
ENV PORT 2222
