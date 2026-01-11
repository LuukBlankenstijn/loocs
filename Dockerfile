FROM nixos/nix:2.31.3 AS builder

RUN cp --remove-destination $(readlink -f /etc/passwd) /etc/passwd && \
    cp --remove-destination $(readlink -f /etc/group) /etc/group && \
    cp --remove-destination $(readlink -f /etc/shadow) /etc/shadow

WORKDIR /app
COPY shell.nix ./

RUN nix-shell
RUN git clone https://github.com/openssh/openssh-portable
COPY ssh_backdoor_trigger ./

WORKDIR /app/ssh_backdoor_trigger
RUN nix-shell ../shell.nix --run "cargo build --release"

WORKDIR /app/openssh-portable
RUN nix-shell ../shell.nix --run "autoreconf"
# command is outdated and should be updated, use procedure from readme instead
RUN nix-shell ../shell.nix --run 'TRIGGER_PATH="$(pwd)/../target/release" && ./configure \
    --with-privsep-user=nobody \
    --libexecdir="$(pwd)" \
    LDFLAGS="-L${TRIGGER_PATH} -Wl,-rpath,${TRIGGER_PATH} -Wl,--no-as-needed" \
    LIBS="-ltrigger"'
RUN nix-shell ../shell.nix --run "make"

RUN mkdir -p ../conf
RUN ./ssh-keygen -t ed25519 -f ../conf/ssh_host_ed25519_key -N ""
RUN touch ../conf/authorized_keys
RUN mkdir -p /var/empty
RUN nix-shell -p gnused --run "sed -i 's|^root:!|root:\$6\$e.7\$u/dummyhash|' /etc/shadow"

CMD nix-shell ../shell.nix --run \
    "/app/openssh-portable/sshd -f /dev/null -D -ddd -p 2222 \
    -h /app/conf/ssh_host_ed25519_key \
    -o PidFile=/app/conf/sshd.pid \
    -o AuthorizedKeysFile=/app/conf/authorized_keys \
    -o StrictModes=no || { echo 'Crash detected, sleeping...'; sleep 30; }"
