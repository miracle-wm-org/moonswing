PREFIX  ?= $(HOME)/.local
BINDIR  := $(PREFIX)/bin
APPDIR  := $(PREFIX)/lib/graceful-shell
DATADIR := $(PREFIX)/share/graceful-shell

BUNDLE  := build/linux/x64/release/bundle

.PHONY: all build install uninstall clean

all: build

build:
	flutter build linux --release

install: build
	install -d $(BINDIR) $(APPDIR) $(DATADIR)
	install -m 755 $(BUNDLE)/graceful_shell $(APPDIR)/graceful_shell
	cp -r $(BUNDLE)/lib/. $(APPDIR)/lib/
	cp -r $(BUNDLE)/data/. $(APPDIR)/data/
	install -m 644 assets/wallpaper.jpg $(DATADIR)/wallpaper.jpg
	@printf '#!/bin/sh\nexec "$(APPDIR)/graceful_shell" "$$@"\n' \
		> $(BINDIR)/graceful-shell
	chmod 755 $(BINDIR)/graceful-shell
	@echo "Installed to $(PREFIX). Make sure $(BINDIR) is in your PATH."

uninstall:
	rm -f $(BINDIR)/graceful-shell
	rm -rf $(APPDIR) $(DATADIR)

clean:
	flutter clean
