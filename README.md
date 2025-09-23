# Arch Linux AUR Build Container

This project provides a containerized AUR build server that automatically
builds AUR packages, signs them, and maintains a local repository you can add
to your Arch machines. It supports rebuilding only when the package version or
PKGBUILD changes.

## Features

* Builds AUR packages in a clean container (1/rebuild, not 1/package)
* Automatically resolves pacman dependencies
* GPG signing of packages and repo database
* Maintains a rolling repo in /repo
* Skips rebuilds for unchanged packages; rebuilds when PKGBUILD changes
* Cleans up old packages automatically with paccache

## Setup

### 1. Prepare GPG Keys

Create a GPG key for signing packages and export the public/private keys:

```bash
gpg --full-generate-key

gpg --export-secret-keys YOUR_KEY_ID > /srv/aur-builder/gnupg/secret.gpg
gpg --export YOUR_KEY_ID > /srv/aur-builder/gnupg/pubkey.gpg
```

Ensure that `/srv/aur-builder/gnupg` is docker-writable.

### 2. Prepare Package List

Create a text file listing the aur packages to build, one per line:

```text
yay-bin
swayfx
# Comments are supported
# ...
```

Save as `/srv/aur-builder/packages.txt`.

### 3. Build the image

```bash
docker build -t <registry>/aur-builder:<tag> -f Dockerfile .

# Optional
docker push <registry>/aur-builder:<tag>
```

### 4. Run the Build Server

Run the container to build packages and update the local repo:

```bash
docker run --rm \
  -e GPG_KEY="YOUR_KEY_ID" \
  -e PKGLIST_FILE="/data/pkglist.txt" \
  -v /srv/aur-builder/pkglist.txt:/data/pkglist.txt:ro \
  -v /srv/aur-builder/repo:/repo \
  -v /srv/aur-builder/gnupg:/home/builder/.gnupg \
  <registry>/aur-builder:<tag>
```

Built packages will be placed in `/srv/aur-builder/repo`. The repo database
will be updated and signed automatically.

### 5. Add the Repo to Your Machines

Add the following to `/etc/pacman.conf` on your Arch machines:

```text
[aur]
SigLevel = Required
Server = http://<server ip or hostname>/repo
```

Import your public key on each client:

```bash
pacman-key --add pubkey.gpg
pacman-key --lsign-key YOUR_KEY_ID
```
