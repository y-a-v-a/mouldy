.PHONY: build test app run demo install notarize release snapshots clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open build/Mould.app

# The whole hour in one minute.
demo: app
	build/Mould.app/Contents/MacOS/Mould --speed 60

# Prefers ~/Applications when it exists, otherwise /Applications. Override with: make install DEST=/some/dir
DEST ?= $(shell [ -d "$$HOME/Applications" ] && echo "$$HOME/Applications" || echo /Applications)

install: app
	@pkill -x Mould 2>/dev/null || true
	rm -rf "$(DEST)/Mould.app"
	ditto build/Mould.app "$(DEST)/Mould.app"
	@echo "Installed to $(DEST)/Mould.app"

# Developer ID distribution: sign (automatic in 'app'), notarize, staple, zip.
notarize: app
	./scripts/notarize.sh

release: notarize
	@echo "Upload build/Mould.zip"

snapshots: build
	mkdir -p docs
	for m in 10 25 45 60; do .build/debug/Mould --snapshot docs/orange-$$m.png --at $$m --size 1280x800 --scale 1 --seed 3; done
	.build/debug/Mould --snapshot docs/strawberry-45.png --at 45 --size 1280x800 --scale 1 --seed 5 --theme strawberry
	.build/debug/Mould --snapshot docs/compost-45.png --at 45 --size 1280x800 --scale 1 --seed 8 --theme compost
	.build/debug/Mould --snapshot docs/closeup.png --at 40 --size 640x400 --scale 2 --seed 3
	.build/debug/Mould --snapshot docs/wipe.png --at 50 --size 1280x800 --scale 1 --seed 3 --wipe 0.45
	cd docs && for f in *.png; do sips -s format jpeg -s formatOptions 82 $$f --out $${f%.png}.jpg >/dev/null && rm $$f; done

clean:
	rm -rf .build build
