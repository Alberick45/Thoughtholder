.PHONY: release

release:
ifndef V
	@echo "Usage: make release V=1.3.0"
	@exit 1
endif
	@powershell -ExecutionPolicy Bypass -File .\thought_holder_flutter\tool\release.ps1 -Version $(V)

