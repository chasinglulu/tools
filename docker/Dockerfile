
# SPDX-License-Identifier: GPL-2.0+
# This Dockerfile is used to build an image containing basic stuff to be used
# to build Xen and run our test suites.

FROM --platform=linux/arm64 ubuntu:latest
LABEL Description=" This image is for building XEN inside a container"
# Make sure apt is happy
ENV DEBIAN_FRONTEND=noninteractive

COPY bin/qemu-aarch64-static /usr/bin/
COPY sources.list /etc/apt/

RUN apt-get update && apt-get upgrade -y && \
    apt-get install vim bash-completion -y && \
    apt-get install build-essential -y && \
    apt-get install bcc bin86 gawk -y && \
    apt-get install bridge-utils iproute2 libcurl4 libcurl4-openssl-dev -y && \
    apt-get install bzip2 transfig tgif -y && \
    apt-get install texinfo texlive-latex-base -y && \
    apt-get install texlive-latex-recommended texlive-fonts-extra texlive-fonts-recommended -y && \
    apt-get install libpci-dev mercurial -y && \
    apt-get install make gcc libc6-dev zlib1g-dev python python-dev -y && \
    apt-get install libncurses5-dev patch libvncserver-dev libsdl-dev -y && \
    apt-get install iasl libbz2-dev e2fslibs-dev git-core uuid-dev ocaml ocaml-findlib libx11-dev -y && \
    apt-get install bison flex xz-utils libyajl-dev -y && \
    apt-get install gettext libpixman-1-dev libaio-dev markdown pandoc -y && \
    apt-get install python3-dev libfdt-dev -y && \
    apt-get install libsystemd-dev -y && \
    apt-get install libnl-3-dev -y

#RUN groupadd -g 1007 xen
RUN useradd -m -d /home/xen -s /bin/bash -u 1007 -U xen
RUN apt-get install sudo && \
    usermod -G sudo xen && \
    echo "xen:xen" | chpasswd

RUN apt-get install bear -y