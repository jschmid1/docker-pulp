#!/bin/bash -e

GPG_KEY=/etc/gpg/gpg_key

if [[ -r "$GPG_KEY" ]]; then
    echo "[INFO] Enabling Signing API"
    # Import private key
    gpg --import $GPG_KEY
elif [[ ! -r "${GPG_KEY}" && "${PULP_TEST}" -eq 1 ]]; then
    echo "Could not find GPG key. Generating new"
    if [[ $(gpg --list-keys | wc -l) -eq 0 ]]; then
    gpg --batch --no-tty --pinentry-mode loopback --gen-key <<EOF
Key-Type: 1
Key-Length: 2048
Subkey-Type: 1
Subkey-Length: 2048
Name-Real: Tester
%no-protection
Name-Email: test@test.com
Expire-Date: 0
EOF
fi
else

echo -e "Could not load GPG key. "
echo -e "If you're running this locally pass PULP_TEST=1 to generate a dummy key"
echo -e "Aborting.."
exit 1

fi

# Export public key
gpg --export -a > /tmp/public.key
# Export key fingerprint
gpg --with-fingerprint --with-colons /tmp/public.key 2>/dev/null | grep fpr: | head -n1 | cut -d: -f10 > /tmp/public.fpr

echo -e "5\ny\n" | gpg --batch --pinentry-mode loopback --yes --no-tty --command-fd 0 --expert --edit-key "$(cat /tmp/public.fpr)" trust

pulpcore-manager shell < /opt/pulp/lib/register-signing-api.py

REDIS_URL=${PULP_REDIS_URL:-"localhost:6379"}
WORKER_NAME=${WORKER_NAME:-"worker@%h"}
exec rq worker --url "$REDIS_URL" -n "$WORKER_NAME" -w 'pulpcore.tasking.worker.PulpWorker' --disable-job-desc-logging
