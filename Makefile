PREFIX  ?= $(HOME)/.local
BINDIR  := $(PREFIX)/bin
APPDIR  := $(PREFIX)/lib/graceful-shell
DATADIR := $(PREFIX)/share/graceful-shell

BUNDLE  := build/linux/x64/release/bundle

PAMDIR  ?= /etc/pam.d

.PHONY: all build install install-pam uninstall uninstall-pam clean

all: build

build:
	flutter build linux --release

install: build
	install -d $(BINDIR) $(APPDIR) $(DATADIR)
	install -m 755 $(BUNDLE)/graceful_shell $(APPDIR)/graceful_shell
	cp -r $(BUNDLE)/lib/. $(APPDIR)/lib/
	cp -r $(BUNDLE)/data/. $(APPDIR)/data/
	install -m 644 assets/wallpaper.jpg $(DATADIR)/wallpaper.jpg
	install -m 644 assets/lock-wallpaper.jpg $(DATADIR)/lock-wallpaper.jpg
	@printf '#!/bin/sh\nexec "$(APPDIR)/graceful_shell" "$$@"\n' \
		> $(BINDIR)/graceful-shell
	chmod 755 $(BINDIR)/graceful-shell
	@echo "Installed to $(PREFIX). Make sure $(BINDIR) is in your PATH."
	@echo "For the lock screen, also run: sudo make install-pam"

# Separate target because it writes outside PREFIX and needs root. Without it
# the lock screen still works, falling back to the `login` PAM service.
install-pam:
	install -d $(PAMDIR)
	install -m 644 pam/graceful-shell $(PAMDIR)/graceful-shell
	@echo "Installed PAM service to $(PAMDIR)/graceful-shell."

uninstall:
	rm -f $(BINDIR)/graceful-shell
	rm -rf $(APPDIR) $(DATADIR)

uninstall-pam:
	rm -f $(PAMDIR)/graceful-shell

clean:
	flutter clean
