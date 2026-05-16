PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

FRAMEWORKS = -framework AVFoundation -framework AppKit -framework CoreMedia -framework Foundation
LINKER_FLAGS = -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

cam: cam.swift Info.plist
	swiftc cam.swift -o cam $(FRAMEWORKS) $(LINKER_FLAGS)
	codesign --force --sign - cam

install: cam
	install -d $(BINDIR)
	install cam $(BINDIR)/cam

uninstall:
	rm -f $(BINDIR)/cam

clean:
	rm -f cam

.PHONY: install uninstall clean
