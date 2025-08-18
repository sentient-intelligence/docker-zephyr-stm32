# Zephyr development image for Espressif targets (e.g. ESP32)

# Settings
ARG UBUNTU_VERSION=24.04
ARG USERNAME="zephyr-builder"
ARG PASSWORD="zephyr"
# ARG ZEPHYR_RTOS_VERSION=4.2.0
# Use commit instead of version to stay consistent across builds
ARG ZEPHYR_RTOS_COMMIT=21c942f18c7f6a4338752ca5c39a746f1034393b
ARG TOOLCHAIN_LIST="-t arm-zephyr-eabi -t aarch64-zephyr-elf"

ARG VS_CODE_SERVER_VERSION=4.93.1
ARG VS_CODE_SERVER_PORT=8800
ARG VS_CODE_EXT_CPPTOOLS_VERSION=1.22.10
ARG VS_CODE_EXT_HEX_EDITOR_VERSION=1.11.1
ARG VS_CODE_EXT_CMAKETOOLS_VERSION=1.19.52
ARG VS_CODE_EXT_NRF_DEVICETREE_VERSION=2024.9.26

ARG WGET_ARGS="-q --show-progress --progress=bar:force:noscroll"
ARG VIRTUAL_ENV=/opt/venv

#-------------------------------------------------------------------------------
# Select Base Image and Dependencies

# Use Ubuntu as the base image
FROM ubuntu:${UBUNTU_VERSION}

# Redeclare arguments after FROM
ARG USERNAME
ARG PASSWORD
ARG ZEPHYR_RTOS_VERSION
ARG ZEPHYR_RTOS_COMMIT
ARG VS_CODE_SERVER_VERSION
ARG VS_CODE_SERVER_PORT
ARG VS_CODE_EXT_CPPTOOLS_VERSION
ARG VS_CODE_EXT_HEX_EDITOR_VERSION
ARG VS_CODE_EXT_CMAKETOOLS_VERSION
ARG VS_CODE_EXT_NRF_DEVICETREE_VERSION
ARG TOOLCHAIN_LIST
ARG WGET_ARGS
ARG VIRTUAL_ENV
ARG TARGETARCH

#-------------------------------------------------------------------------------
# Set default shell during Docker image build to bash
SHELL ["/bin/bash", "-c"]

# Check if the target architecture is either x86_64 (amd64) or arm64 (aarch64)
RUN if [ "$TARGETARCH" = "amd64" ] || [ "$TARGETARCH" = "arm64" ]; then \
        echo "Architecture $TARGETARCH is supported."; \
    else \
        echo "Unsupported architecture: $TARGETARCH"; \
        exit 1; \
    fi

#-------------------------------------------------------------------------------
# Set non-interactive frontend for apt-get to skip any user confirmations
ENV DEBIAN_FRONTEND=noninteractive

#-------------------------------------------------------------------------------
# Install base packages
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y upgrade
RUN DEBIAN_FRONTEND=noninteractive apt-get -y update && \
    apt-get install --no-install-recommends -y \
        dos2unix \
        ca-certificates \
        file \
        locales \
        git \
        build-essential \
        cmake \
        ninja-build gperf \
        device-tree-compiler \
        wget \
        curl \
        python3 \
        python3-pip \
        python3-venv \
        xz-utils \
        dos2unix \
        vim \
        nano \
        mc \
        openssh-server

#-------------------------------------------------------------------------------
# Add user and relevant settings
RUN useradd -d /opt/${USERNAME} -m -s /bin/bash ${USERNAME}
RUN usermod -aG sudo ${USERNAME}
RUN mkdir -p /opt/zephyr
RUN echo "${USERNAME}:${PASSWORD}" | chpasswd
USER ${USERNAME}

# Set up a Python virtual environment
ENV VIRTUAL_ENV=${VIRTUAL_ENV}
RUN python3 -m venv ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:$PATH"

# Install west
RUN python3 -m pip install --no-cache-dir west

# Clean up stale packages
RUN apt-get clean -y && \
    apt-get autoremove --purge -y && \
    rm -rf /var/lib/apt/lists/*

# Set up directories
RUN mkdir -p /workspace/ && \
    mkdir -p /opt/toolchains

# Set up sshd working directory
RUN mkdir -p /var/run/sshd && \
    chmod 0755 /var/run/sshd

# Allow root login via SSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Expose SSH port
EXPOSE 22

#-------------------------------------------------------------------------------
# Zephyr RTOS Setup

# Set Zephyr environment variables
ENV ZEPHYR_RTOS_VERSION=${ZEPHYR_RTOS_VERSION}

# Install Zephyr
RUN cd /opt/toolchains && \
    git clone https://github.com/zephyrproject-rtos/zephyr.git && \
    cd zephyr && \
    git checkout ${ZEPHYR_RTOS_COMMIT} && \
    python3 -m pip install -r scripts/requirements-base.txt && \
	ZEPHYR_SDK_VERSION="v$(cat SDK_VERSION)"
 







# install Zephyr SDK
USER ${USERNAME}
RUN mkdir /opt/zephyr/sdk
WORKDIR /opt/zephyr/sdk
RUN wget https://github.com/zephyrproject-rtos/meta-zephyr-sdk/releases/download/0.9.1/zephyr-sdk-0.9.1-setup.run
RUN chmod +x zephyr-sdk-0.9.1-setup.run
USER root
RUN ./zephyr-sdk-0.9.1-setup.run
USER zephyr
ENV ZEPHYR_GCC_VARIANT zephyr
ENV ZEPHYR_SDK_INSTALL_DIR /opt/zephyr-sdk/

# for open-ocd
USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y -q libtool automake pkg-config libusb-1.0-0 libusb-1.0-0-dev
USER zephyr
WORKDIR /opt/zephyr
RUN git clone https://github.com/erwango/openocd-stm32.git
WORKDIR /opt/zephyr/openocd-stm32
RUN ./bootstrap
RUN ./configure --enable-maintainer-mode --enable-stlink
RUN make

# set initial path
WORKDIR /opt/zephyr
