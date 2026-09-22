PREFIX  ?= $(HOME)/.local
BINDIR  := $(PREFIX)/bin
APPDIR  := $(PREFIX)/lib/moonswing
DATADIR := $(PREFIX)/share/moonswing

BUNDLE  := build/linux/x64/release/bundle

PAMDIR  ?= /etc/pam.d

# The portal backend is discovered through XDG_DATA_HOME / XDG_CONFIG_HOME,
# not PREFIX: xdg-desktop-portal only searches those (plus system dirs), so
# a custom PREFIX cannot move them.
XDG_DATA_HOME   ?= $(HOME)/.local/share
XDG_CONFIG_HOME ?= $(HOME)/.config
PORTALDIR    := $(XDG_DATA_HOME)/xdg-desktop-portal/portals
PORTALCONFDIR := $(XDG_CONFIG_HOME)/xdg-desktop-portal

.PHONY: all build install install-pam install-portal uninstall uninstall-pam \
	uninstall-portal clean

all: build

build:
	flutter build linux --release

install: build install-portal
	install -d $(BINDIR) $(APPDIR) $(DATADIR)
	install -m 755 $(BUNDLE)/moonswing $(APPDIR)/moonswing
	cp -r $(BUNDLE)/lib/. $(APPDIR)/lib/
	cp -r $(BUNDLE)/data/. $(APPDIR)/data/
	install -m 644 assets/wallpaper.jpg $(DATADIR)/wallpaper.jpg
	install -m 644 assets/lock-wallpaper.jpg $(DATADIR)/lock-wallpaper.jpg
	@printf '#!/bin/sh\nexec "$(APPDIR)/moonswing" "$$@"\n' \
		> $(BINDIR)/moonswing
	chmod 755 $(BINDIR)/moonswing
	@echo "Installed to $(PREFIX). Make sure $(BINDIR) is in your PATH."
	@echo "For the lock screen, also run: sudo make install-pam"

# Separate target because it writes outside PREFIX and needs root. Without it
# the lock screen still works, falling back to the `login` PAM service.
install-pam:
	install -d $(PAMDIR)
	install -m 644 pam/moonswing $(PAMDIR)/moonswing
	@echo "Installed PAM service to $(PAMDIR)/moonswing."

# Registers the shell as the ScreenCast portal backend. No D-Bus activation
# file: the shell owns the name from session start, and screen sharing should
# not be able to start the shell.
install-portal:
	install -d $(PORTALDIR) $(PORTALCONFDIR)
	install -m 644 portal/moonswing.portal $(PORTALDIR)/moonswing.portal
	@if [ -f $(PORTALCONFDIR)/mir-portals.conf ]; then \
		echo "Kept existing $(PORTALCONFDIR)/mir-portals.conf — to use the"; \
		echo "shell's screen-share picker it needs:"; \
		echo "  [preferred]"; \
		echo "  org.freedesktop.impl.portal.ScreenCast=moonswing"; \
	else \
		install -m 644 portal/moonswing-portals.conf \
			$(PORTALCONFDIR)/mir-portals.conf; \
		echo "Installed $(PORTALCONFDIR)/mir-portals.conf."; \
	fi
	@echo "Run 'systemctl --user restart xdg-desktop-portal' to pick this up."

uninstall: uninstall-portal
	rm -f $(BINDIR)/moonswing
	rm -rf $(APPDIR) $(DATADIR)

uninstall-pam:
	rm -f $(PAMDIR)/moonswing

uninstall-portal:
	rm -f $(PORTALDIR)/moonswing.portal
	@echo "Left $(PORTALCONFDIR)/mir-portals.conf in place (user config)."

clean:
	flutter clean
