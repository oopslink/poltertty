# Poltertty Makefile
# Quick build commands for development and release
# See docs/build-rules.md for detailed documentation

.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

##@ Development

.PHONY: dev
dev: ## Build in Dev mode (incremental, fast)
	@echo "$(CYAN)==> Building Dev mode (Debug, incremental)$(NC)"
	@xattr -rc ~/Library/Developer/Xcode/DerivedData/Ghostty-*/Build/Products/Debug/Poltertty.app 2>/dev/null || true
	@./scripts/build.sh dev

.PHONY: dev-clean
dev-clean: clean-xcode ## Build in Dev mode with full cache cleanup
	@echo "$(CYAN)==> Building Dev mode (Debug, clean)$(NC)"
	@./scripts/build.sh dev

.PHONY: run-dev
run-dev: dev ## Build and run Dev version
	@echo "$(GREEN)==> Running Dev version$(NC)"
	@open ~/Library/Developer/Xcode/DerivedData/Ghostty-*/Build/Products/Debug/Poltertty.app 2>/dev/null || \
		echo "$(YELLOW)App location may vary in DerivedData. Please locate and run manually.$(NC)"

.PHONY: check
check: ## Check Swift compilation errors only
	@echo "$(CYAN)==> Checking Swift errors$(NC)"
	@xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty -configuration Debug build 2>&1 | \
		grep "\.swift:" | grep "error:" || echo "$(GREEN)No Swift compilation errors found$(NC)"

##@ Release

.PHONY: release
release: clean-xcode ## Build in Release mode (Optimized) with cache cleanup
	@echo "$(CYAN)==> Building Release mode$(NC)"
	@./scripts/build.sh release

.PHONY: package
package: ## Build Release and create zip package
	@echo "$(CYAN)==> Building and packaging Release$(NC)"
	@./scripts/build.sh release --zip

.PHONY: run-release
run-release: release ## Build and run Release version
	@echo "$(GREEN)==> Running Release version$(NC)"
	@open macos/build/ReleaseLocal/Poltertty.app

##@ Maintenance

.PHONY: clean
clean: ## Clean all build artifacts
	@echo "$(YELLOW)==> Cleaning build artifacts$(NC)"
	@rm -rf \
		zig-out .zig-cache \
		macos/build \
		macos/GhosttyKit.xcframework
	@echo "$(GREEN)Clean complete$(NC)"

.PHONY: clean-xcode
clean-xcode: ## Clean Xcode DerivedData and extended attributes
	@echo "$(YELLOW)==> Cleaning Xcode DerivedData$(NC)"
	@rm -rf ~/Library/Developer/Xcode/DerivedData/Ghostty-*
	@echo "$(YELLOW)==> Removing extended attributes$(NC)"
	@xattr -cr macos/ 2>/dev/null || true
	@echo "$(GREEN)Xcode cache cleaned$(NC)"

.PHONY: clean-all
clean-all: clean clean-xcode ## Clean everything including Xcode cache
	@echo "$(GREEN)All build artifacts cleaned$(NC)"

##@ Setup

.PHONY: init-git-hooks
init-git-hooks: ## Install local git hooks (protect main branch from direct push)
	@./scripts/init-git-hooks.sh

##@ Legacy (from upstream)

init:
	@echo You probably want to run "zig build" instead.
.PHONY: init

# glad updates the GLAD loader. To use this, place the generated glad.zip
# in this directory next to the Makefile, remove vendor/glad and run this target.
#
# Generator: https://gen.glad.sh/
glad: vendor/glad
.PHONY: glad

vendor/glad: vendor/glad/include/glad/gl.h vendor/glad/include/glad/glad.h

vendor/glad/include/glad/gl.h: glad.zip
	rm -rf vendor/glad
	mkdir -p vendor/glad
	unzip glad.zip -dvendor/glad
	find vendor/glad -type f -exec touch '{}' +

vendor/glad/include/glad/glad.h: vendor/glad/include/glad/gl.h
	@echo "#include <glad/gl.h>" > $@

##@ Help

.PHONY: help
help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\n$(CYAN)Usage:$(NC)\n  make $(YELLOW)<target>$(NC)\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(GREEN)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
