FROM ubuntu:20.04 as builder

# Project build directory
ARG BUILD_DIR=/build/

# Kernel source
ARG KERNEL_GIT=https://github.com/raspberrypi/linux.git
ARG KERNEL_BRANCH=rpi-5.4.y

# Distro download
ARG DISTRO_FILE=2021-05-07-raspios-buster-arm64-lite
ARG DISTRO_IMG=https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2021-05-28/$DISTRO_FILE.zip

# Kernel compile options
ARG KERNEL=kernel8
ARG ARCH=arm64
ARG CROSS_COMPILE=aarch64-linux-gnu-
ARG CORES=2

# Install dependencies
ARG DEBIAN_FRONTEND="noninteractive"
RUN apt-get update \
 && apt install -y \
    bc \
    bison \
    crossbuild-essential-arm64 \
    flex \
    git \
    libssl-dev \
    libc6-dev \
    make \
    wget \
    unzip \
    libguestfs-tools \
    linux-image-generic

ENTRYPOINT echo "hello world!"

# # Clone the kernel source repo
# RUN git clone --single-branch --branch $KERNEL_BRANCH $KERNEL_GIT $BUILD_DIR/linux/

# # Use predefined build configuration
# COPY ./.config $BUILD_DIR/linux/

# # Build kernel, kernel modules and device tree blobs
# RUN make -C $BUILD_DIR/linux/ -j$CORES Image modules dtbs

# # Download distro and rename to distro.img
# RUN wget -nv -O $BUILD_DIR/$DISTRO_FILE.zip $DISTRO_IMG \
#  && unzip $BUILD_DIR/$DISTRO_FILE.zip -d $BUILD_DIR \
#  && mv $BUILD_DIR/$DISTRO_FILE.img $BUILD_DIR/distro.img

# # Extract distro partitions content
# RUN mkdir /mnt/root /mnt/boot \
#  && guestfish add $BUILD_DIR/distro.img : run : mount /dev/sda1 / : copy-out / /mnt/boot : umount / : mount /dev/sda2 / : copy-out / /mnt/root

# # Replace kernel, kernel modules and device tree blobs
# RUN rm -r /mnt/root/lib/modules/* \
#  && rm /mnt/boot/*.dtb \
#  && rm /mnt/boot/overlays/* \
#  && rm /mnt/boot/kernel8.img \
#  && cp $BUILD_DIR/linux/arch/arm64/boot/Image /mnt/boot/kernel8.img \
#  && make -C $BUILD_DIR/linux/ INSTALL_MOD_PATH=/mnt/root modules_install \
#  && cp $BUILD_DIR/linux/arch/arm64/boot/dts/broadcom/*.dtb /mnt/boot/ \
#  && cp $BUILD_DIR/linux/arch/arm64/boot/dts/overlays/*.dtb* /mnt/boot/overlays/

# # Create new image from modified configuration
# RUN guestfish -N distro2.img=bootroot:vfat:ext4:2G \
#  && guestfish add distro2.img : run : mount /dev/sda1 / : glob copy-in /mnt/boot/* / : umount / : mount /dev/sda2 / : glob copy-in /mnt/root/* / 

# COPY ./tools/copy.sh /build/
# ENTRYPOINT /build/copy.sh

# RUN make -C /linux bcmrpi3_defconfig

# FROM ubuntu:20.04

# RUN echo "hello world!"