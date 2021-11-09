#!/usr/bin/env bash

FILE_PATH=$(realpath "$1")
SIGNATURE_PATH="${FILE_PATH}.asc"
INLINE_SIGNATURE_PATH="/var/lib/pulp/InRelease"

export GNUPGHOME=/var/lib/pulp/.gnupg
ADMIN_ID=$(gpg --list-keys --with-colons | grep fpr: | head -n1 | cut -d: -f10)

# Create a detached signature
gpg --batch \
    --pinentry-mode loopback \
    --yes \
    --detach-sign \
    --armor \
    --local-user "${ADMIN_ID}" \
    --output "${SIGNATURE_PATH}" \
    "${FILE_PATH}"

# Create an inline signature
gpg --batch \
    --pinentry-mode loopback \
    --yes \
    --clearsign \
    --local-user "${ADMIN_ID}" \
    --output "${INLINE_SIGNATURE_PATH}" \
    "${FILE_PATH}"

json=$(cat <<-END
    {
        "file": "${FILE_PATH}",
        "signature": "${SIGNATURE_PATH}",
        "signatures": {
            "inline": "${INLINE_SIGNATURE_PATH}"
        }
    }
END
)

# Check the exit status
STATUS=$?
if [[ $STATUS -eq 0 ]]; then
    echo "${json}"
else
    exit $STATUS
fi
