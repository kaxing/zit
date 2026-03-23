PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
ZIG ?= zig
OPT ?= ReleaseSmall

.PHONY: install uninstall clean

zit: zit.zig
	$(ZIG) build-exe $< -O$(OPT) -femit-bin=zit -fno-unwind-tables -fstrip

install: zit
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 zit $(DESTDIR)$(BINDIR)/zit

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/zit

clean:
	rm -f zit
