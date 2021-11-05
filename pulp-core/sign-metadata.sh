#!/usr/bin/env bash

FILE_PATH=$1
SIGNATURE_PATH="$FILE_PATH.asc"
DETACHED_SIGNATURE_PATH="Release.gpg"
INLINE_SIGNATURE_PATH="InRelease"

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

# Deb Repositories want the detached-signature with a certain name
ln -sf "${SIGNATURE_PATH}" "${DETACHED_SIGNATURE_PATH}"

json=$(cat <<-END
    {
        "file": "${FILE_PATH}",
        "signature": "${SIGNATURE_PATH}",
        "signatures": {
            "inline": "${INLINE_SIGNATURE_PATH}",
            "detached": "${DETACHED_SIGNATURE_PATH}"
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
