#!/usr/bin/env bash

# Adapted from:
#  * https://blackboxsw.github.io/seed-snaps-using-maas.html

if [ -f build-settings.sh ]; then
    source build-settings.sh
else
    echo "ERROR! Could not source build-settings.sh."
    exit 1
fi

SEED_DIR="/var/lib/snapd/seed"
SEED_DIR="$HOME/seed"

# Preseeded snaps should be downloaded from a versioned channel
SEED_CHANNEL="stable/ubuntu-${REL_VER}"

STRICT_SNAPS="core pulsemixer"
CLASSIC_SNAPS="ubuntu-mate-welcome software-boutique"
SEED_SNAPS="${STRICT_SNAPS} ${CLASSIC_SNAPS}"

mkdir -p ${SEED_DIR}/snaps
mkdir -p ${SEED_DIR}/assertions

# Download the published snaps and their related assert files
# core snap is required for seeding
cd ${SEED_DIR}/snaps
for SEED_SNAP in ${SEED_SNAPS}; do
  if [ "${SEED_SNAP}" == "core" ] || [ "${SEED_SNAP}" == "core16" ] || [ "${SEED_SNAP}" == "core18" ]; then
    snap download --channel=stable "${SEED_SNAP}"
  else
    snap download --channel="${SEED_CHANNEL}" "${SEED_SNAP}"
  fi
  mv ${SEED_SNAP}*.assert ../assertions
done
cd -

# Create model and account assertions
snap known --remote model series=16 model=generic-classic brand-id=generic > ${SEED_DIR}/assertions/generic-classic.model
ACCOUNT_KEY=$(grep "^sign-key-sha3-384" ${SEED_DIR}/assertions/generic-classic.model | cut -d':' -f2 | sed 's/ //g')
snap known --remote account-key public-key-sha3-384=${ACCOUNT_KEY} > ${SEED_DIR}/assertions/generic.account-key
snap known --remote account account-id=generic > ${SEED_DIR}/assertions/generic.account

# Create the seed.yaml: the manifest of snaps to install
echo "snaps:" > ${SEED_DIR}/seed.yaml
for ASSERT_FILE in ${SEED_DIR}/assertions/*.assert; do
    SNAP_NAME=$(grep "^snap-name" ${ASSERT_FILE} | cut -d':' -f2 | sed 's/ //g')
    SNAP_REVISION=$(grep "^snap-revision" ${ASSERT_FILE} | cut -d':' -f2 | sed 's/ //g')
    if [ "${SNAP_NAME}" == "core" ] || [ "${SNAP}" == "core16" ] || [ "${SNAP}" == "core18" ]; then
      SNAP_CHANNEL="stable"
    else
      SNAP_CHANNEL="${SEED_CHANNEL}"
    fi

    # Classic snaps require a "classic: true" attribute in the seed file
    if [[ $CLASSIC_SNAPS =~ $SNAP_NAME ]]; then
        printf " - name: %s\n   channel: %s\n   classic: true\n   file: %s_%s.snap\n" ${SNAP_NAME} ${SNAP_CHANNEL} ${SNAP_NAME} ${SNAP_REVISION} >> ${SEED_DIR}/seed.yaml
    else
        printf " - name: %s\n   channel: %s\n   file: %s_%s.snap\n" ${SNAP_NAME} ${SNAP_CHANNEL} ${SNAP_NAME} ${SNAP_REVISION} >> ${SEED_DIR}/seed.yaml
    fi
done;
cat ${SEED_DIR}/seed.yaml
