.PHONY: build test release clean install uninstall doctor bench format lint help

# Default target
build:
	swift build

test:
	swift test

release:
	swift build -c release

# Build universal binary (arm64 + x86_64)
universal:
	./scripts/build-release.sh

clean:
	swift package clean
	rm -rf .build

install: release
	@echo "Installing zyquo to /usr/local/bin..."
	cp .build/release/zyquo /usr/local/bin/zyquo
	@echo "Done. Run 'zyquo doctor' to verify."

uninstall:
	rm -f /usr/local/bin/zyquo
	@echo "Uninstalled zyquo."

doctor: build
	swift run zyquo doctor

bench: release
	./scripts/bench.sh

format:
	@if command -v swift-format > /dev/null 2>&1; then \
		swift-format format --in-place --recursive Sources/ Tests/; \
	else \
		echo "swift-format not found. Install with: brew install swift-format"; \
	fi

lint:
	@if command -v swiftlint > /dev/null 2>&1; then \
		swiftlint lint Sources/; \
	else \
		echo "swiftlint not found. Install with: brew install swiftlint"; \
	fi

help:
	@echo "Zyquo Makefile targets:"
	@echo "  build      Build debug binary"
	@echo "  test       Run all tests"
	@echo "  release    Build release binary"
	@echo "  universal  Build universal binary (arm64 + x86_64)"
	@echo "  clean      Clean build artifacts"
	@echo "  install    Install to /usr/local/bin"
	@echo "  uninstall  Remove from /usr/local/bin"
	@echo "  doctor     Run diagnostics"
	@echo "  bench      Run performance benchmarks"
	@echo "  format     Format source code (requires swift-format)"
	@echo "  lint       Lint source code (requires swiftlint)"
