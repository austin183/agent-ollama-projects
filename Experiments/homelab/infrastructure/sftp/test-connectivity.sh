#!/bin/sh
# Test SFTP connectivity and file transfer

set -e

echo "=== SFTP Connectivity Test ==="
echo ""

# Test 1: Connect and list
echo "Test 1: Connecting and listing directory..."
sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no "${SFTP_USER}@sftp" <<EOF
ls
bye
EOF
echo "✓ Connection successful"
echo ""

# Test 2: Upload file
echo "Test 2: Uploading test file..."
echo "Hello from SFTP test $(date)" > /tmp/hello-sftp.txt
sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no "${SFTP_USER}@sftp" <<EOF
cd /files
put /tmp/hello-sftp.txt
bye
EOF
echo "✓ File uploaded"
echo ""

# Test 3: Download file
echo "Test 3: Downloading test file..."
sshpass -p "$SFTP_PASSWORD" sftp -o StrictHostKeyChecking=no "${SFTP_USER}@sftp" <<EOF
cd /files
get hello-sftp.txt /tmp/hello-sftp-downloaded.txt
bye
EOF
echo "✓ File downloaded"
echo ""

# Test 4: Verify content
echo "Test 4: Verifying downloaded content..."
if grep -q "Hello from SFTP test" /tmp/hello-sftp-downloaded.txt; then
    echo "✓ Content verified"
    echo ""
    echo "=== All Tests Passed ==="
    rm -f /tmp/hello-sftp.txt /tmp/hello-sftp-downloaded.txt
    exit 0
else
    echo "✗ Content mismatch"
    exit 1
fi
