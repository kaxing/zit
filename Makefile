PREFIX ?= $(HOME)
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
ZIG ?= zig
OPT ?= ReleaseSmall
TARGET ?=
STRIP ?= 1

ZIG_FLAGS := -O$(OPT) -femit-bin=zit -fno-llvm -fno-unwind-tables
ifeq ($(STRIP),1)
ZIG_FLAGS += -fstrip
endif
ifneq ($(TARGET),)
ZIG_FLAGS += -target $(TARGET)
endif

.PHONY: install uninstall clean

zit: zit.zig
	$(ZIG) build-exe $< $(ZIG_FLAGS)

install: zit
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 zit $(DESTDIR)$(BINDIR)/zit

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/zit

clean:
	rm -f zit
