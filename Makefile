PREFIX   ?= $(HOME)/.local
BINDIR   ?= $(PREFIX)/bin
SHAREDIR ?= $(PREFIX)/share/dco

.PHONY: install uninstall regen-devcontainer test check-domains help

help:
	@echo "make install [PREFIX=...]     install dco to \$$(BINDIR), templates+config to \$$(SHAREDIR)"
	@echo "make uninstall [PREFIX=...]   remove installed dco and \$$(SHAREDIR)"
	@echo "make regen-devcontainer       regenerate this repo's own .devcontainer/ from templates/"
	@echo "make test                     run the bats test suite (needs bats: npm install -g bats)"
	@echo "make check-domains            resolve every config/allowlist.txt domain (needs real network + dig)"

# Escaped for safe use inside a sed replacement (backslash, &, and the
# s|...|...| delimiter all need escaping or PREFIX values containing them
# corrupt or break the substitution).
SHAREDIR_SED_SAFE := $(shell printf '%s' "$(SHAREDIR)" | sed -e 's/[\\&|]/\\&/g')

install:
	install -d "$(BINDIR)" "$(SHAREDIR)/templates" "$(SHAREDIR)/config"
	sed 's|@SHAREDIR@|$(SHAREDIR_SED_SAFE)|g' dco.in > "$(BINDIR)/dco.tmp"
	mv -f "$(BINDIR)/dco.tmp" "$(BINDIR)/dco"
	chmod +x "$(BINDIR)/dco"
	cp -r templates/. "$(SHAREDIR)/templates/"
	chmod +x "$(SHAREDIR)/templates/init-firewall.sh"
	cp config/allowlist.txt "$(SHAREDIR)/config/"
	@echo "installed $(BINDIR)/dco (SHAREDIR=$(SHAREDIR))"

uninstall:
	@[ -e "$(BINDIR)/dco" ] || [ -d "$(SHAREDIR)" ] || \
	  echo "warning: nothing found at BINDIR=$(BINDIR) / SHAREDIR=$(SHAREDIR) — if you installed with a custom PREFIX, pass it here too: make uninstall PREFIX=..." >&2
	rm -f "$(BINDIR)/dco"
	rm -rf "$(SHAREDIR)"

# NOTE: unlike dco.in's own scaffold_devcontainer() helper, this target has
# no non-destructive guard — it always overwrites this repo's own
# dogfooded top-level .devcontainer/ files. Recoverable via git (this repo
# is one), just don't expect it to preserve local edits.
regen-devcontainer:
	mkdir -p .devcontainer
	cp -r templates/. .devcontainer/
	cp config/allowlist.txt .devcontainer/allowlist.txt
	chmod +x .devcontainer/init-firewall.sh

test:
	bats test/

check-domains:
	bash test/check-allowlist-domains.sh
