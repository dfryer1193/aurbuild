#!/bin/bash
set -euo pipefail

export GNUPGHOME=/home/builder/.gnupg

REPO_DIR=/repo
PKGLIST_FILE=${PKGLIST_FILE:-/repo/pkglist.txt}
GPG_KEY=${GPG_KEY:-""}
BASE_BUILD_ARGS="--noconfirm --clean --cleanbuild"
BUILD_ARGS="${BASE_BUILD_ARGS}"
BASE_REPO_ARGS="-s -v"
REPO_ARGS="${BASE_REPO_ARGS}"

if [ -n "$GPG_KEY" ]; then
    if [ ! -f "${GNUPGHOME}/trustdb.gpg" ]; then
        gpg --batch --yes --update-trustdb
    fi

    gpg --batch --yes --import $GNUPGHOME/private.key
    gpg --batch --yes --import $GNUPGHOME/pubkey.key

    FPR=$(gpg --list-keys --with-colons "$GPG_KEY" | awk -F: '/fpr/ {print $10; exit}')
    if [ -n "$FPR" ]; then
        gpg --batch --yes --trust-model always --import-ownertrust <<EOF
${FPR}:6:
EOF

        BUILD_ARGS="${BUILD_ARGS} --sign --key ${FPR}"
        REPO_ARGS="${REPO_ARGS} --sign --key ${FPR}"
    else
        echo "ERROR: Could not find fingerprint for GPG key ${GPG_KEY}"
        exit 1
    fi
fi

mkdir -p "${REPO_DIR}"

if [ ! -f "${PKGLIST_FILE}" ]; then
    echo "ERROR: Package list file not found at ${PKGLIST_FILE}"
    exit 1
fi

mapfile -t PACKAGES < <(grep -Ev '^\s*#|^\s*$' "${PKGLIST_FILE}")

echo "==> Packages to build:"
printf '   %s\n' "${PACKAGES[@]}"

for pkg in "${PACKAGES[@]}"; do
    echo "==> Cloning ${pkg}..."
    if [ ! -d "$pkg" ]; then
        git clone "https://aur.archlinux.org/${pkg}.git"
    fi

    (
        cd "$pkg"
        git pull --ff-only || true

        # Load package metadata
        source PKGBUILD
        pkg_fullver="${pkgver}-${pkgrel}"
        pkg_file_pattern="${REPO_DIR}/${pkg}-${pkg_fullver}-*.pkg.tar.zst"
        hash_file="${REPO_DIR}/${pkg}-${pkg_fullver}.pkgbuild.sha256"

        # Calculate PKGBUILD hash
        pkgbuild_hash=$(sha256sum PKGBUILD | awk '{print $1}')

        # Check if package already exists with matching PKGBUILD hash
        if ls $pkg_file_pattern >/dev/null 2>&1; then
            if [[ -f "$hash_file" ]] && grep -q "$pkgbuild_hash" "$hash_file"; then
                echo "==> Skipping ${pkg}, version ${pkg_fullver} already built with matching PKGBUILD."
                exit 0
            else
                echo "==> Rebuilding ${pkg}, PKGBUILD changed for version ${pkg_fullver}."
            fi
        fi

        echo "==> Resolving dependencies for ${pkg}..."
        all_deps=("${depends[@]:-}" "${makedepends[@]:-}")
        if [ ${#all_deps[@]} -gt 0 ]; then
            yay -Sy --noconfirm --needed --asdeps "${all_deps[@]}"
        fi

        echo "==> Building ${pkg} ${pkg_fullver}..."
        makepkg ${BUILD_ARGS}
        mv -v *.pkg.tar.zst* "${REPO_DIR}/"

        # Save new PKGBUILD hash
        echo "$pkgbuild_hash" > "$hash_file"
    )
done

echo "=>> Cleaning up old packages..."
paccache -r -k 2 -c "${REPO_DIR}"

echo "=>> Updating repo..."
repo-add ${REPO_ARGS} "${REPO_DIR}/repo.db.tar.gz" "${REPO_DIR}/"*.pkg.tar.zst

