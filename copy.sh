
#!/usr/bin/bash

mkdir -p rootfs
set -x

part_map=$(sudo kpartx -av ubuntu-rootfs-aarch64.img)

sudo mount /dev/mapper/$(echo "$part_map" | sed -n '5p' | awk '{print $3}') rootfs/

# copy boot config
sudo mkdir -p rootfs/extlinux/
sudo cp extlinux.conf rootfs/extlinux/

# copy kernel images
sudo cp linux/arch/arm64/boot/Image rootfs/
sudo cp linux/arch/arm64/boot/Image.gz rootfs/
sudo cp linux/arch/arm64/boot/dts/hobot/hobot-sigi-virt.dtb rootfs/
sudo cp linux/arch/arm64/boot/dts/hobot/hobot-sigie-virt.dtb rootfs/

#sudo cp /home/xinlu.wang/27-J6-Gitlab/kernel-6.1/arch/arm64/boot/Image rootfs/
#sudo cp /home/xinlu.wang/27-J6-Gitlab/kernel-6.1/arch/arm64/boot/dts/hobot/hobot-sigi-virt.dtb rootfs/

# copy initramfs image
sudo cp buildroot/output/images/rootfs.cpio.lz4 rootfs/

# copy xen image
#sudo cp -r xen-tools/4.17/install/boot/xen* rootfs/
sudo cp xen/xen/xen rootfs/

sudo umount rootfs
sudo kpartx -dv ubuntu-rootfs-aarch64.img

sync

