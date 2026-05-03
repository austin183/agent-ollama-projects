#!/bin/sh
set -e

# Generate host keys if they don't exist
for key_type in ed25519 rsa; do
  [ -f /etc/ssh/ssh_host_${key_type}_key ] || \
    ssh-keygen -t "$key_type" -f "/etc/ssh/ssh_host_${key_type}_key" -N '' -q
done

# Create users from SFTP_USERS
for user_data in $SFTP_USERS; do
  /usr/local/bin/create-sftp-user "$user_data"
done

# Setup authorized_keys for key-based auth
USERNAME=$(echo "$SFTP_USERS" | cut -d: -f1)
USER_UID=$(id -u "$USERNAME")
USER_GID=$(id -g "$USERNAME")

mkdir -p "/home/${USERNAME}/.ssh"
cp /tmp/id_rsa.pub "/home/${USERNAME}/.ssh/authorized_keys"
chmod 700 "/home/${USERNAME}/.ssh"
chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"
chown -R "${USER_UID}:${USER_GID}" "/home/${USERNAME}/.ssh"

# Pre-create backups directory (inside chroot, so user can write to it)
mkdir -p "/home/${USERNAME}/backups/repo"
chown -R "${USER_UID}:${USER_GID}" "/home/${USERNAME}/backups"

# Start sshd
exec /usr/sbin/sshd -D
