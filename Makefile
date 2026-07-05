PREFIX   ?= $(HOME)/.local
BINDIR   ?= $(PREFIX)/bin
SHAREDIR ?= $(PREFIX)/share/dco

.PHONY: install uninstall regen-devcontainer help

help:
	@echo "make install [PREFIX=...]     install dco to \$$(BINDIR), templates+config to \$$(SHAREDIR)"
	@echo "make uninstall [PREFIX=...]   remove installed dco and \$$(SHAREDIR)"
	@echo "make regen-devcontainer       regenerate this repo's own .devcontainer/ from templates/"

install:
	install -d "$(BINDIR)" "$(SHAREDIR)/templates" "$(SHAREDIR)/config"
	sed 's|@SHAREDIR@|$(SHAREDIR)|g' dco.in > "$(BINDIR)/dco"
	chmod +x "$(BINDIR)/dco"
	cp templates/devcontainer.json templates/Dockerfile templates/init-firewall.sh "$(SHAREDIR)/templates/"
	chmod +x "$(SHAREDIR)/templates/init-firewall.sh"
	cp config/allowlist.txt "$(SHAREDIR)/config/"
	@echo "installed $(BINDIR)/dco (SHAREDIR=$(SHAREDIR))"

uninstall:
	rm -f "$(BINDIR)/dco"
	rm -rf "$(SHAREDIR)"

regen-devcontainer:
	rm -rf .devcontainer
	mkdir -p .devcontainer
	cp templates/devcontainer.json templates/Dockerfile templates/init-firewall.sh .devcontainer/
	cp config/allowlist.txt .devcontainer/allowlist.txt
	chmod +x .devcontainer/init-firewall.sh
