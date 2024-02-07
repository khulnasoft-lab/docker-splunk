#!/bin/bash
# Copyright 2018-2024 Splunk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

# Generate UTF-8 char map and locale
# Reinstalling local English def for now, removed in minimal image: https://bugzilla.redhat.com/show_bug.cgi?id=1665251
dnf -y --nodocs install glibc-langpack-en

# Currently there is no access to the UTF-8 char map. The following command is commented out until
# the base container can generate the locale.
# localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
# We get around the gen above by forcing the language install, and then pointing to it.
export LANG=en_US.utf8

# Install utility packages
dnf -y --nodocs install wget sudo shadow-utils procps tar make gcc \
                             openssl-devel bzip2-devel libffi-devel findutils \
                             libssh-devel libcurl-devel glib2-devel ncurses-devel
# Patch security updates
dnf -y --nodocs update gnutls kernel-headers libdnf librepo libnghttp2 nettle \
                            libpwquality libxml2 systemd-libs lz4-libs curl \
                            rpm rpm-libs sqlite-libs cyrus-sasl-lib vim expat \
                            openssl-libs xz-libs zlib libsolv file-libs pcre \
                            libarchive libgcrypt libksba libstdc++ json-c gnupg

# Reinstall tzdata (originally stripped from minimal image): https://bugzilla.redhat.com/show_bug.cgi?id=1903219
dnf -y --nodocs reinstall tzdata || dnf -y --nodocs update tzdata

## Install Python and necessary packages
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py
rm -f get-pip.py
ln -sf /usr/bin/python3 /usr/bin/python

# Install splunk-ansible dependencies
pip install setuptools
pip -q --no-cache-dir install six wheel requests cryptography==3.3.2 ansible==3.4.0 urllib3==1.26.5 jmespath --upgrade
cd /

# Remove tests packaged in python libs
find /usr/lib/ -depth \( -type d -a -not -wholename '*/ansible/plugins/test' -a \( -name test -o -name tests -o -name idle_test \) \) -exec rm -rf '{}' \;
find /usr/lib/ -depth \( -type f -a -name '*.pyc' -o -name '*.pyo' -o -name '*.a' \) -exec rm -rf '{}' \;
find /usr/lib/ -depth \( -type f -a -name 'wininst-*.exe' \) -exec rm -rf '{}' \;
ldconfig

# Cleanup
dnf remove -y make gcc openssl-devel bzip2-devel findutils glib2-devel glibc-devel cpp binutils \
                   keyutils-libs-devel krb5-devel libcom_err-devel libffi-devel libcurl-devel \
                   libselinux-devel libsepol-devel libssh-devel libverto-devel libxcrypt-devel \
                   ncurses-devel pcre2-devel zlib-devel
dnf clean all

# Install busybox direct from the multiarch since EPEL isn't available for Amazon Linux 2023
arch=$(uname -m) 
if [ "$arch" == "aarch64" ]; then
    export BUSYBOX_ARCH="armv8l"
else
    export MY_ENV_VAR="$arch"
fi
wget -O /bin/busybox https://busybox.net/downloads/binaries/1.28.1-defconfig-multiarch/busybox-"$BUSYBOX_ARCH"
chmod +x /bin/busybox

# Enable busybox symlinks
cd /bin
BBOX_LINKS=( clear find diff hostname killall netstat nslookup ping ping6 readline route syslogd tail traceroute vi )
for item in "${BBOX_LINKS[@]}"
do
  ln -s busybox $item || true
done
chmod u+s /bin/ping
groupadd sudo

echo "
## Allows people in group sudo to run all commands
%sudo  ALL=(ALL)       ALL" >> /etc/sudoers

# Clean
dnf clean all
rm -rf /install.sh /anaconda-post.log /var/log/anaconda/*
