FROM archlinux:base-devel

RUN pacman -Syu --noconfirm \
	git \
	sudo \
	gnupg \
	pacman-contrib \
	&& pacman -Scc --noconfirm

# Disable systemd pacman hooks
RUN mkdir -p /etc/pacman.d/hooks.disabled && \
	mv /etc/pacman.d/hooks/* /etc/pacman.d/hooks.disabled/ || true

RUN useradd -m -s /bin/bash builder && \
	echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/builder && \
	chmod 0440 /etc/sudoers.d/builder

COPY ./build.sh /usr/local/bin/build.sh
RUN chmod +x /usr/local/bin/build.sh

VOLUME ["/repo"]

USER builder
WORKDIR /home/builder

RUN git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin \
	&& cd /tmp/yay-bin \
	&& makepkg -si --noconfirm \
	&& rm -rf /tmp/yay-bin

CMD ["/usr/local/bin/build.sh"]
