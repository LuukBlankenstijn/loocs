# XZ exploit reproduction

**Offensive Computer Security Project**

This repository contains code to reproduce the XZ vulnerability in a virtual environment. For this, a vulnerable version of xz-utils is installed, together with a version of sshd that works with that version of xz-utils. Then, the docker containers are ran using Kathara, which emulates the network between the containers.

## Code explanation

In this section we explain the most important parts of the code.

### Dockerfile

The main part of this code is in the Dockerfile. The docker image is based on Debian 12. Additionally, multiple packages are installed, including ones needed for networking and debugging tools.

Then the xz-bot repository is cloned into the container. This repository contains an script that can be used to exploit the vulnerability in xz-utils. The goal of our project is to improve this script to get a reverse shell.

After these installation steps, the vulnerable version of xz-utils is installed. To do this, some config needs to be changed to allow the installation of this older version. Then, also an older version of openssh is installed. An older version is needed, because the exploit doesn't work with the latest version of openssh.

To allow us to log connection attempts, the source code of the openssh server is downloaded, patched and build. After that it is installed on the container.

Then, some ssh configuration is changed to allow root login and password authentication.

The next step is to patch the liblzma so file, to add our own public key, replacing the attackers public key. For this, the patch from the xz-bot repository is used. After this patch is applied, the liblzma so file is installed.

Finally, the container opens an ssh shell to allow us to run commands on in and exploit the vulnerability.

### Kathara

Kathara is used to emulate the network between the docker containers. The kathara configuration is in the lab.conf file. This file defines two containers, a server and a client. Both containers use the docker image built using the Dockerfile and are bridged, meaning they will be connected to the host network.

In addition to the lab.conf file, a server.startup and a client.startup file are present. These files contain commands that are run when the respective container starts. In both files an ip address is assigned to the eth0 network interface and a name server is added to the resolv.conf file in the client container, to allow us to resolve domain names.

In the server.startup file, additionally an ssh deamon is started.

### Run

Make sure docker and kathara are installed.
Then run

```
docker build --tag=xz-vulnerablility-server .

```

After this completes, you can run `kathara lstart` to start the demo

