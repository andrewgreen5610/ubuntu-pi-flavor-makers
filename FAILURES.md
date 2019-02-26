# ifupdown

root      1047 27125  0 14:48 pts/4    00:00:00       sudo ./build-image.sh
root      1048  1047  0 14:48 pts/4    00:00:00         bash ./build-image.sh
root      1058  1048  0 14:48 pts/4    00:00:00           /usr/bin/qemu-arm-static /bin/bash /usr/local/bin/ubuntu-mate-core.sh
root      1149  1058  0 14:48 pts/4    00:00:09             /usr/bin/qemu-arm-static /usr/bin/apt-get -y install ubuntu-mate-core^
root      1177  1149  0 14:56 pts/5    00:00:00               /usr/bin/qemu-arm-static /usr/bin/dpkg --status-fd 40 --configure --pending
root      1624  1177  0 14:56 pts/5    00:00:00                 /usr/bin/qemu-arm-static /bin/sh /var/lib/dpkg/info/ifupdown.postinst configure
root      1627  1624 99 14:56 pts/5    00:20:30                   /usr/bin/qemu-arm-static /usr/bin/perl /usr/sbin/addgroup --quiet --system netdev

# ssl-cert

root      1047 27125  0 14:48 pts/4    00:00:00       sudo ./build-image.sh
root      1048  1047  0 14:48 pts/4    00:00:00         bash ./build-image.sh
root      1058  1048  0 14:48 pts/4    00:00:00           /usr/bin/qemu-arm-static /bin/bash /usr/local/bin/ubuntu-mate-core.sh
root      1149  1058  0 14:48 pts/4    00:00:10             /usr/bin/qemu-arm-static /usr/bin/apt-get -y install ubuntu-mate-core^
root      1177  1149  0 14:56 pts/5    00:00:00               /usr/bin/qemu-arm-static /usr/bin/dpkg --status-fd 40 --configure --pending
root      6426  1177  0 15:18 pts/5    00:00:00                 /usr/bin/qemu-arm-static /usr/bin/perl -w /usr/share/debconf/frontend /var/lib/dpkg/info/ssl-cert.postinst configure
root      6447  6426  0 15:18 pts/5    00:00:00                   /usr/bin/qemu-arm-static /bin/sh -e /var/lib/dpkg/info/ssl-cert.postinst configure
root      6450  6447 99 15:18 pts/5    00:17:24                     /usr/bin/qemu-arm-static /usr/bin/getent group ssl-cert