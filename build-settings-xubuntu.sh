#!/usr/bin/env bash

########################################################################
#
# Copyright (C) 2015 Martin Wimpress <code@ubuntu-mate.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
########################################################################

FLAVOUR="xubuntu"
FLAVOUR_NAME="Xubuntu"
RELEASE="bionic"
MAJ_VER="18"
MIN_VER="04"
PNT_VER="2"
REL_VER="${MAJ_VER}.${MIN_VER}"
VERSION="${REL_VER}.${PNT_VER}"
QUALITY="-alpha"
ARCHITECTURE="armhf"
ENABLE_VC4=0
META_PACKAGES="xubuntu-core xubuntu-desktop"

# Either 'ext4' or 'f2fs'
FS_TYPE="ext4"

# Target image size, will be represented in GB
if [ "${FS_TYPE}" == "ext4" ]; then
    FS_SIZE=5
elif [ "${FS_TYPE}" == "f2fs" ]; then
    FS_SIZE=6
fi

if [ "${ARCHITECTURE}" == "armhf" ]; then
    SUB_ARCH="raspi"
elif [ "${ARCHITECTURE}" == "arm64" ]; then
    SUB_ARCH="raspi3"
fi

# Either 0 or 1.
# - 0 don't make generic rootfs tarball
# - 1 make a generic rootfs tarball
MAKE_TARBALL=0

TARBALL="${FLAVOUR}-${VERSION}${QUALITY}-desktop-${ARCHITECTURE}+${SUB_ARCH}.tar.xz"
IMAGE="${FLAVOUR}-${VERSION}${QUALITY}-desktop-${ARCHITECTURE}+${SUB_ARCH}-${FS_TYPE}.img"
BASEDIR=${HOME}/PiFlavourMaker/${RELEASE}/${ARCHITECTURE}
BUILDDIR=${BASEDIR}/${FLAVOUR}
BASE_R=${BASEDIR}/base
DESKTOP_R=${BUILDDIR}/desktop
DEVICE_R=${BUILDDIR}/pi
export TZ=UTC

# Override OEM_CONFIG here if required. Either 0 or 1.
# - 0 ardcode a user. username and password will $FLAVOUR/$FLAVOUR
# - 1 use oem-config. username and password for OEM session are oem/oem
OEM_CONFIG=1

if [ ${OEM_CONFIG} -eq 1 ]; then
    USERNAME="oem"
else
    USERNAME="${FLAVOUR}"
fi