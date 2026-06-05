#!/usr/bin/env bash
# Enable passwordless SSH between builder and ministry (Vagrant insecure key).
set -euo pipefail

SSH_DIR="/home/vagrant/.ssh"
PUB_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iALLlDMbLXpXozYpat9xQHkhRKD4YBKLWUKKsN8Tz7/2/4mfCRMpWLwzx/X7IZAnHbTs82MXq+5GKeH8uaYqBLiwHTeufZBIGWXi4DfnK9TpFhSvRvbKxhO/6/c8Fya24K+t+nEep7C8DQtNLsKy+ZHIztCZBk0B09yxNRf/e6v/r0PsH16BKs0Xt1OlXLbhGYD4nhb2NAdUQjsK8Spb+qGJFDvgxu99ef5KnQX+zyK8G61sKTPhfeZ8MzKBXEngEmnbaQBGSsaxhfIS47ZyriuMvSZFMvOsONz1ZEJNWzII_snBEg893Bvv212-xO9sUxDFFTOIPxJLSNBLUe3g1TtM1iVLa7LsycwTUUx4wZ14aM807A8tOV5kNJRK7uLfPJQHzRWQ== vagrant insecure public key"

install -d -m 700 -o vagrant -g vagrant "$SSH_DIR"
AUTH="${SSH_DIR}/authorized_keys"
touch "$AUTH"
chown vagrant:vagrant "$AUTH"
chmod 600 "$AUTH"
grep -qF "$PUB_KEY" "$AUTH" 2>/dev/null || echo "$PUB_KEY" >>"$AUTH"
