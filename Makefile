.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	bash scripts/make-app.sh

run: app
	open build/MacSweep.app

# Copies to /Applications so the Full Disk Access grant sticks to a stable path.
install: app
	rm -rf /Applications/MacSweep.app
	cp -R build/MacSweep.app /Applications/MacSweep.app
	open /Applications/MacSweep.app

clean:
	rm -rf .build build
