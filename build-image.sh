#!/usr/bin/env bash

########################################################################
#
# Copyright (C) 2015 - 2019 Martin Wimpress <code@ubuntu-mate.org>
# Copyright (C) 2015 Rohith Madhavan <rohithmadhavan@gmail.com>
# Copyright (C) 2015 Ryan Finnie <ryan@finnie.org>
#
# See the included LICENSE file.
#
########################################################################

set -x

if [ -f build-settings.sh ]; then
    source build-settings.sh
else
    echo "ERROR! Could not source build-settings.sh."
    exit 1
fi

if [ $(id -u) -ne 0 ]; then
    echo "ERROR! Must be root."
    exit 1
fi

function nspawn() {
    # Create basic resolv.conf for bind mounting inside the container
    echo "nameserver 1.1.1.1" > $BASEDIR/resolv.conf
    mkdir -p $R/boot/firmware 2>/dev/null

    # Make sure the container has a machine-id
    systemd-machine-id-setup --root $R --print

    # Spawn the container, bind mount resolv.conf and set the hostname
    systemd-nspawn --bind-ro=$BASEDIR/resolv.conf:/etc/resolv.conf --bind=$R/boot/firmware:/boot/firmware --hostname=${FLAVOUR} -D $R "$@"
}

function sync_to() {
    local TARGET="${1}"
    if [ ! -d "${TARGET}" ]; then
        mkdir -p "${TARGET}"
    fi
    rsync -aHAXx --progress --delete ${R}/ ${TARGET}/
}

# Base debootstrap
function bootstrap() {
    # Required tools
    apt-get -y install binfmt-support debootstrap f2fs-tools \
    pxz qemu-user-static rsync systemd-container ubuntu-keyring \
    whois xz-utils

    # Use the same base system for all flavours.
    qemu-debootstrap --verbose --arch=armhf $RELEASE $R http://ports.ubuntu.com/
}

function generate_locale() {
    for LOCALE in $(nspawn locale | cut -d'=' -f2 | grep -v : | sed 's/"//g' | uniq); do
        if [ -n "${LOCALE}" ]; then
            nspawn locale-gen $LOCALE
        fi
    done
}

# Set up initial sources.list
function apt_sources() {
    cat <<EOM >$R/etc/apt/sources.list
deb http://ports.ubuntu.com/ ${RELEASE} main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE} main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-updates main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-updates main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-security main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-security main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-backports main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-backports main restricted universe multiverse
EOM
}

function apt_upgrade() {
    nspawn apt-get update
    nspawn apt-get -y -u dist-upgrade
}

function apt_clean() {
    nspawn apt-get -y autoremove
    nspawn apt-get clean
}

# Install Ubuntu standard
function ubuntu_standard() {
    nspawn apt-get -y install ubuntu-minimal^
    nspawn apt-get -y install ubuntu-standard^
    nspawn apt-get -y install software-properties-common
}

# Install meta packages
function install_meta() {
    local META="${1}"
    local RECOMMENDS="${2}"
    if [ "${RECOMMENDS}" == "--no-install-recommends" ]; then
        echo 'APT::Install-Recommends "false";' > $R/etc/apt/apt.conf.d/99noinstallrecommends
    else
        local RECOMMENDS=""
    fi

    nspawn apt-get -y install ${RECOMMENDS} ${META}^

    cat <<EOM >$R/usr/local/bin/${1}.sh
#!/usr/bin/env bash
service dbus start
apt-get -f install
dpkg --configure -a
service dbus stop
EOM

    chmod +x $R/usr/local/bin/${1}.sh
    nspawn /usr/local/bin/${1}.sh
    rm $R/usr/local/bin/${1}.sh

    if [ "${RECOMMENDS}" == "--no-install-recommends" ]; then
        rm $R/etc/apt/apt.conf.d/99noinstallrecommends
    fi
}

function create_groups() {
    nspawn groupadd -f --system gpio
    nspawn groupadd -f --system i2c
    nspawn groupadd -f --system input
    nspawn groupadd -f --system spi
    cp files/adduser.local $R/usr/local/sbin/
}

# Create default user
function create_user() {
    local DATE=$(date +%m%H%M%S)
    local PASSWD=$(mkpasswd -m sha-512 ${USERNAME} ${DATE})

    if [ ${OEM_CONFIG} -eq 1 ]; then
        nspawn addgroup --gid 29999 oem
        nspawn adduser --gecos "OEM Configuration (temporary user)" --add_extra_groups --disabled-password --gid 29999 --uid 29999 ${USERNAME}
    else
        nspawn adduser --gecos "${FLAVOUR_NAME}" --add_extra_groups --disabled-password ${USERNAME}
    fi
    nspawn usermod -a -G sudo -p ${PASSWD} ${USERNAME}
}

# Prepare oem-config for first boot.
function prepare_oem_config() {
    if [ ${OEM_CONFIG} -eq 1 ]; then
        if [ "${FLAVOUR}" == "kubuntu" ]; then
            nspawn apt-get -y install --no-install-recommends oem-config-kde ubiquity-frontend-kde ubiquity-ubuntu-artwork
        else
            nspawn apt-get -y install --no-install-recommends oem-config-gtk ubiquity-frontend-gtk ubiquity-ubuntu-artwork
        fi

        if [ "${FLAVOUR}" == "ubuntu" ]; then
            nspawn apt-get -y install --no-install-recommends oem-config-slideshow-ubuntu
        elif [ "${FLAVOUR}" == "ubuntu-budgie" ]; then
            nspawn apt-get -y install --no-install-recommends oem-config-slideshow-ubuntu-budgie
            # Force the slideshow to use Ubuntu Budgie artwork.
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-budgie/' $R/usr/lib/ubiquity/plugins/ubi-usersetup.py
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-budgie/' $R/usr/sbin/oem-config-remove-gtk
        elif [ "${FLAVOUR}" == "ubuntu-mate" ]; then
            nspawn apt-get -y install --no-install-recommends oem-config-slideshow-ubuntu-mate
            # Force the slideshow to use Ubuntu MATE artwork.
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-mate/' $R/usr/lib/ubiquity/plugins/ubi-usersetup.py
            sed -i 's/oem-config-slideshow-ubuntu/oem-config-slideshow-ubuntu-mate/' $R/usr/sbin/oem-config-remove-gtk
        fi
        cp -a $R/usr/lib/oem-config/oem-config.service $R/lib/systemd/system
        cp -a $R/usr/lib/oem-config/oem-config.target $R/lib/systemd/system
        nspawn /bin/systemctl enable oem-config.service
        nspawn /bin/systemctl enable oem-config.target
        nspawn /bin/systemctl set-default oem-config.target
    fi
}

function configure_ssh() {
    nspawn apt-get -y install openssh-server sshguard
    nspawn /bin/systemctl disable ssh.service
    nspawn /bin/systemctl disable sshguard.service
}

function configure_network() {
    # Set up hosts
    echo ${FLAVOUR} >$R/etc/hostname
    cat <<EOM >$R/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       ${FLAVOUR}
EOM
}

function disable_services() {
    # Disable brltty because it spams syslog with SECCOMP errors
    if [ -e $R/sbin/brltty ]; then
        chroot $R /bin/systemctl disable brltty.service
    fi

    # Disable irqbalance because it is of little, if any, benefit on ARM.
    if [ -e $R/etc/init.d/irqbalance ]; then
        nspawn /bin/systemctl disable irqbalance
    fi

    # Disable TLP because it is redundant on ARM devices.
    if [ -e $R/etc/default/tlp ]; then
        sed -i s'/TLP_ENABLE=1/TLP_ENABLE=0/' $R/etc/default/tlp
        nspawn /bin/systemctl disable tlp.service
        nspawn /bin/systemctl disable tlp-sleep.service
    fi

    # Disable apport because these images are not official
    if [ -e $R/etc/default/apport ]; then
        sed -i s'/enabled=1/enabled=0/' $R/etc/default/apport
        nspawn /bin/systemctl disable apport.service
        nspawn /bin/systemctl disable apport-forward.socket
    fi

    # Disable whoopsie because these images are not official
    if [ -e $R/usr/bin/whoopsie ]; then
        nspawn /bin/systemctl disable whoopsie.service
    fi

    # Disable kerneloops because these images are not official
    if [ -e $R/usr/sbin/kerneloops ]; then
        sed -i s'/ENABLED=1/ENABLED=0/' $R/etc/default/kerneloops
        nspawn /bin/systemctl disable kerneloops.service
    fi

    # Disable mate-optimus
    if [ -e $R/usr/share/mate/autostart/mate-optimus.desktop ]; then
        rm -f $R/usr/share/mate/autostart/mate-optimus.desktop || true
    fi
}

function configure_hardware() {
    local FS="${1}"

    # Install the RPi PPA
    nspawn apt-add-repository --yes --no-update ppa:ubuntu-pi-flavour-makers/ppa
    nspawn apt-get -y update

    # Firmware Kernel installation
    nspawn apt-get -y --no-install-recommends install linux-image-raspi2
    nspawn apt-get -y install linux-firmware-raspi2 u-boot-rpi u-boot-tools
    rsync -aHAXx $R/lib/firmware/4.*-raspi2/device-tree/ $R/boot/firmware/

    # Install fbturbo drivers on non composited desktop OS
    # fbturbo causes VC4 to fail
    if [ "${FLAVOUR}" == "lubuntu" ] || [ "${FLAVOUR}" == "ubuntu-mate" ] || [ "${FLAVOUR}" == "xubuntu" ]; then
        nspawn apt-get -y install xserver-xorg-video-fbturbo
    fi

    # pi-top poweroff and brightness utilities
    cp files/pi-top-* $R/usr/bin/
    chown root:root $R/usr/bin/pi-top-*
    chmod +x $R/usr/bin/pi-top-*

    # Install the Ubuntu port of raspi-config & Raspberry Pi system tweaks
    nspawn apt-get -y install raspi-config raspberrypi-sys-mods
    # Enable / partition resize
    #nspawn systemctl enable resize-fs.service

    # Install bluetooth firmware and helpers
    nspawn apt-get -y install pi-bluetooth

    # Add /boot/config.txt
    cp files/config.txt $R/boot/firmware/
    sed -i 's/#kernel=""/kernel=vmlinuz/' $R/boot/firmware/config.txt
    sed -i 's/#initramfs initramf.gz 0x00800000/initramfs initrd.img followkernel/' $R/boot/firmware/config.txt

    # Add /boot/cmdline.txt
    echo "net.ifnames=0 dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=${FS} elevator=deadline fsck.repair=yes rootwait quiet splash plymouth.ignore-serial-consoles" > $R/boot/firmware/cmdline.txt

    # Enable VC4 on composited desktops
    if [ "${FLAVOUR}" == "kubuntu" ] || [ "${FLAVOUR}" == "ubuntu" ] || [ "${FLAVOUR}" == "ubuntu-budgie" ]; then
      echo "dtoverlay=vc4-kms-v3d" >> $R/boot/config.txt
    fi

    # Create swapfile
    fallocate -l 128M $R/swapfile
    chmod 600 $R/swapfile
    mkswap -L swap $R/swapfile

    # Set up fstab
    cat <<EOM >$R/etc/fstab
LABEL=writable     /               ${FS}  defaults,noatime  0  0
LABEL=system-boot  /boot/firmware  vfat   defaults          0  1
/swapfile          none            swap   sw                0  0
EOM

    # Install flash-kernel last so it doesn't try (and fail) to detect the
    # platform in the chroot.
    nspawn apt-get -y install flash-kernel
    VMLINUZ="$(ls -1 $R/boot/vmlinuz-* | sort | tail -n 1)"
    cp "${VMLINUZ}" $R/boot/firmware/vmlinuz
    INITRD="$(ls -1 $R/boot/initrd.img-* | sort | tail -n 1)"
    cp "${INITRD}" $R/boot/firmware/initrd.img
}

function install_software() {
    return 0

    # Python
    nspawn apt-get -y install \
    python-minimal python3-minimal \
    python-dev python3-dev \
    python-pip python3-pip \
    python-setuptools python3-setuptools

    # Python extras a Raspberry Pi hacker expects to be available ;-)
    nspawn apt-get -y install \
    raspi-gpio \
    python-rpi.gpio python3-rpi.gpio \
    python-gpiozero python3-gpiozero \
    pigpio python-pigpio python3-pigpio \
    python-serial python3-serial \
    python-spidev python3-spidev \
    python-smbus python3-smbus \
    python-astropi python3-astropi \
    python-drumhat python3-drumhat \
    python-envirophat python3-envirophat \
    python-pianohat python3-pianohat \
    python-pantilthat python3-pantilthat \
    python-scrollphat python3-scrollphat \
    python-st7036 python3-st7036 \
    python-sn3218 python3-sn3218 \
    python-piglow python3-piglow \
    python-microdotphat python3-microdotphat \
    python-mote python3-mote \
    python-motephat python3-motephat \
    python-explorerhat python3-explorerhat \
    python-rainbowhat python3-rainbowhat \
    python-sense-hat python3-sense-hat \
    python-sense-emu python3-sense-emu sense-emu-tools \
    python-picamera python3-picamera \
    python-rtimulib python3-rtimulib \
    python-pygame

    nspawn pip2 install codebug_tether
    nspawn pip3 install codebug_tether

    if [ "${FLAVOUR}" == "ubuntu-mate" ]; then
        # Install the Minecraft PPA
        nspawn apt-add-repository -y ppa:flexiondotorg/minecraft
        nspawn apt-add-repository -y ppa:ubuntu-mate-dev/welcome
        nspawn apt-get update

        # Python IDLE
        nspawn apt-get -y install idle idle3

        # YouTube DL
        nspawn apt-get -y install ffmpeg rtmpdump
        nspawn apt-get -y --no-install-recommends install ffmpeg youtube-dl
        nspawn apt-get -y install youtube-dlg

        # Scratch (nuscratch)
        # - Requires: scratch and used to require wiringpi
        cp deb/scratch_1.4.20131203-2_all.deb $R/tmp/scratch.deb
        cp deb/wiringpi_2.32_armhf.deb $R/tmp/wiringpi.deb
        nspawn apt-get -y install /tmp/wiringpi.deb
        nspawn apt-get -y install /tmp/scratch.deb
        nspawn apt-get -y install nuscratch

        # Minecraft
        nspawn apt-get -y install minecraft-pi python-picraft python3-picraft --allow-downgrades

        # Sonic Pi
        cp files/jackd.conf $R/tmp/
        nspawn debconf-set-selections -v /tmp/jackd.conf
        nspawn apt-get -y install sonic-pi
    fi
}

function clean_up() {
    rm -f $R/etc/apt/*.save || true
    rm -f $R/etc/apt/sources.list.d/*.save || true
    rm -f $R/etc/resolvconf/resolv.conf.d/original
    rm -f $R/run/*/*pid || true
    rm -f $R/run/*pid || true
    rm -f $R/run/cups/cups.sock || true
    rm -f $R/run/uuidd/request || true
    rm -f $R/etc/*-
    rm -rf $R/tmp/*
    rm -f $R/var/crash/*
    rm -f $R/var/lib/urandom/random-seed

    # Build cruft
    rm -f $R/var/cache/debconf/*-old || true
    rm -f $R/var/lib/dpkg/*-old || true
    rm -f $R/var/cache/bootstrap.log || true
    truncate -s 0 $R/var/log/lastlog || true
    truncate -s 0 $R/var/log/faillog || true
    mkdir -p $R/var/log/installer

    # SSH host keys
    rm -f $R/etc/ssh/ssh_host_*key
    rm -f $R/etc/ssh/ssh_host_*.pub

    # Potentially sensitive.
    rm -f $R/root/.bash_history
    rm -f $R/root/.ssh/known_hosts

    # Remove bogus home directory
    if [ -d $R/home/${SUDO_USER} ]; then
        rm -rf $R/home/${SUDO_USER} || true
    fi

    # Machine-specific, so remove in case this system is going to be
    # cloned.  These will be regenerated on the first boot.
    rm -f $R/etc/udev/rules.d/70-persistent-cd.rules
    rm -f $R/etc/udev/rules.d/70-persistent-net.rules
    rm -f $R/etc/NetworkManager/system-connections/*
    [ -L $R/var/lib/dbus/machine-id ] || rm -f $R/var/lib/dbus/machine-id
    echo '' > $R/etc/machine-id

    # Build system state tracking files
    rm -rf $R/tmp/.stage_* || true
}

function make_raspi2_image() {
    # Build the image file
    local FS="${1}"
    local SIZE_IMG="${2}"
    local SIZE_BOOT="128MiB"

    if [ "${FS}" != "ext4" ] && [ "${FS}" != 'f2fs' ]; then
        echo "ERROR! Unsupport filesystem requested. Exitting."
        exit 1
    fi

    # Remove old images.
    rm -f "${BASEDIR}/${IMAGE}" || true

    # Create an empty file file.
    dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1MB count=1
    dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1MB count=0 seek=$(( ${SIZE_IMG} * 1000 ))

    # Initialising: msdos
    parted -s ${BASEDIR}/${IMAGE} mktable msdos
    echo "Creating /boot/firmware partition"
    parted -a optimal -s ${BASEDIR}/${IMAGE} mkpart primary fat32 1 "${SIZE_BOOT}"
    echo "Creating / partition"
    parted -a optimal -s ${BASEDIR}/${IMAGE} mkpart primary ext4 "${SIZE_BOOT}" 100%

    PARTED_OUT=$(parted -s ${BASEDIR}/${IMAGE} unit b print)
    BOOT_OFFSET=$(echo "${PARTED_OUT}" | grep -e '^ 1'| xargs echo -n \
    | cut -d" " -f 2 | tr -d B)
    BOOT_LENGTH=$(echo "${PARTED_OUT}" | grep -e '^ 1'| xargs echo -n \
    | cut -d" " -f 4 | tr -d B)

    ROOT_OFFSET=$(echo "${PARTED_OUT}" | grep -e '^ 2'| xargs echo -n \
    | cut -d" " -f 2 | tr -d B)
    ROOT_LENGTH=$(echo "${PARTED_OUT}" | grep -e '^ 2'| xargs echo -n \
    | cut -d" " -f 4 | tr -d B)

    BOOT_LOOP=$(losetup --show -f -o ${BOOT_OFFSET} --sizelimit ${BOOT_LENGTH} ${BASEDIR}/${IMAGE})
    ROOT_LOOP=$(losetup --show -f -o ${ROOT_OFFSET} --sizelimit ${ROOT_LENGTH} ${BASEDIR}/${IMAGE})
    echo "/boot/firmware: offset ${BOOT_OFFSET}, length ${BOOT_LENGTH}"
    echo "/:              offset ${ROOT_OFFSET}, length ${ROOT_LENGTH}"

    mkfs.vfat -n system-boot -S 512 -s 16 -v "${BOOT_LOOP}"
    if [ "${FS}" == "ext4" ]; then
        mkfs.ext4 -L writable -m 0 "${ROOT_LOOP}"
    else
        mkfs.f2fs -l writable -o 1 "${ROOT_LOOP}"
    fi

    MOUNTDIR="${BUILDDIR}/mount"
    mkdir -p "${MOUNTDIR}"
    mount -v "${ROOT_LOOP}" "${MOUNTDIR}" -t "${FS}"
    mkdir -p "${MOUNTDIR}/boot/firmware"
    mount -v "${BOOT_LOOP}" "${MOUNTDIR}/boot/firmware" -t vfat
    rsync -aHAXx "$R/" "${MOUNTDIR}/"
    sync
    umount -l "${MOUNTDIR}/boot/firmware"
    umount -l "${MOUNTDIR}"
    losetup -d "${ROOT_LOOP}"
    losetup -d "${BOOT_LOOP}"
}

function make_hash() {
    local FILE="${1}"
    local HASH="sha256"
    local KEY="FFEE1E5C"
    if [ ! -f ${FILE}.${HASH}.sign ]; then
        if [ -f ${FILE} ]; then
            ${HASH}sum ${FILE} > ${FILE}.${HASH}
            sed -i -r "s/ .*\/(.+)/  \1/g" ${FILE}.${HASH}
            gpg --default-key ${KEY} --armor --output ${FILE}.${HASH}.sign --detach-sig ${FILE}.${HASH}
        else
            echo "WARNING! Didn't find ${FILE} to hash."
        fi
    else
        echo "Existing signature found, skipping..."
    fi
}

function make_tarball() {
    if [ ${MAKE_TARBALL} -eq 1 ]; then
        rm -f "${BASEDIR}/${TARBALL}" || true
        tar -cSf "${BASEDIR}/${TARBALL}" $R
        make_hash "${BASEDIR}/${TARBALL}"
    fi
}

function compress_image() {
    if [ ! -e "${BASEDIR}/${IMAGE}.xz" ]; then
        echo "Compressing to: ${BASEDIR}/${IMAGE}.xz"
        pxz ${BASEDIR}/${IMAGE}
    fi
    make_hash "${BASEDIR}/${IMAGE}.xz"
}

function stage_01_base() {
    if [ ! -f "${BASE_R}/tmp/.stage_base" ]; then
        R="${BASE_R}"
        bootstrap
        generate_locale
        apt_sources
        apt_upgrade
        ubuntu_standard
        apt_clean
        touch "$R/tmp/.stage_base"
        sync_to "${DESKTOP_R}"
    fi
}

function stage_02_desktop() {
    if [ ! -f "${DESKTOP_R}/tmp/.stage_desktop" ]; then
        R="${BASE_R}"
        sync_to "${DESKTOP_R}"
        
        R="${DESKTOP_R}"
        if [ "${FLAVOUR}" == "ubuntu-mate" ]; then
            # Install the RPi PPA to get the latest meta package for ubuntu-mate
            nspawn apt-add-repository --yes --no-update ppa:ubuntu-pi-flavour-makers/ppa
            nspawn apt-get -y update
            install_meta ${FLAVOUR}-core
            install_meta ${FLAVOUR}-desktop
        elif [ "${FLAVOUR}" == "xubuntu" ]; then
            install_meta ${FLAVOUR}-core
            install_meta ${FLAVOUR}-desktop
        else
            install_meta ${FLAVOUR}-desktop
        fi

        create_groups
        create_user
        prepare_oem_config
        configure_ssh
        configure_network
        disable_services
        apt_upgrade
        apt_clean
        clean_up
        sync_to ${DEVICE_R}
        make_tarball
        touch "${DESKTOP_R}/tmp/.stage_desktop"
    fi
}

function stage_03_raspi2() {
    # Always start with a clean rootfs
    R="${DESKTOP_R}"
    sync_to ${DEVICE_R}

    R=${DEVICE_R}
    configure_hardware ${FS_TYPE}
    install_software
    apt_upgrade
    apt_clean
    clean_up
    make_raspi2_image ${FS_TYPE} ${FS_SIZE}
}

function stage_04_corrections() {
    R=${DEVICE_R}

    # Insert other corrections here.

    apt_clean
    clean_up
    make_raspi2_image ${FS_TYPE} ${FS_SIZE}
}

stage_01_base
stage_02_desktop
stage_03_raspi2
#stage_04_corrections
#compress_image