FROM rust:1.92-slim-bookworm

WORKDIR /usr/src/ssh_backdoor_trigger
COPY ssh_backdoor_trigger .
RUN cargo build --release

# Install dependencies
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    git \
    libssl-dev \
    libtool \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

# Compile sshd
RUN git clone https://github.com/openssh/openssh-portable
WORKDIR /usr/src/openssh-portable
RUN git checkout V_10_2_P1 && \ 
    autoreconf && \ 
    ./configure && \ 
    make install && \ 
    # add required users and directories
    useradd -r -U -d /var/empty -c "sshd privsep" -s /bin/false sshd && \
    mkdir -p /var/empty && \
    chmod 755 /var/empty

ENTRYPOINT ["env", "LD_PRELOAD=/usr/src/ssh_backdoor_trigger/target/release/libtrigger.so", "/usr/local/sbin/sshd", "-D", "-e", "-p", "2222", "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa"]

