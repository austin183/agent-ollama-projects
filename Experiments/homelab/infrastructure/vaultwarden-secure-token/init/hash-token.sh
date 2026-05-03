#!/bin/sh
set -e

echo "Generating Argon2id PHC string for admin token..."

SALT=$(openssl rand -base64 32)
PHC=$(echo -n "${PLAINTEXT_PASSWORD}" | argon2 "${SALT}" -e -id -k 65540 -t 3 -p 4)

echo "PHC string generated, writing to shared volume..."
echo "${PHC}" > /shared/phc-token

echo "Done. PHC string written to /shared/phc-token"
cat /shared/phc-token
