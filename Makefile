.PHONY: build test app dmg run install clean

build:
	swift build

test:
	swift test

app:
	bash scripts/make-app.sh

dmg:
	bash scripts/make-dmg.sh

run: app
	open build/MacSweep.app

# Copies to /Applications so the Full Disk Access grant sticks to a stable path.
install: app
	osascript -e 'tell application id "com.rahulraj.macsweep" to quit' 2>/dev/null || true
	sleep 1
	rm -rf /Applications/MacSweep.app
	cp -R build/MacSweep.app /Applications/MacSweep.app
	open /Applications/MacSweep.app

clean:
	rm -rf .build build
