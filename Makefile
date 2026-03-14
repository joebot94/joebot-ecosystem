.PHONY: up down status logs tabs run demo package import-db

up:
	./scripts/joebot-stack.sh up

down:
	./scripts/joebot-stack.sh down

status:
	./scripts/joebot-stack.sh status

logs:
	./scripts/joebot-stack.sh logs

tabs:
	./scripts/open-stack-tabs.sh

run: tabs

demo:
	python3 ./scripts/demo_check.py

package:
	./scripts/package-apps.sh

import-db:
	@if [ -z "$(DB)" ]; then \
		echo "Usage: make import-db DB=/path/to/glitch_catalog.db"; \
		exit 1; \
	fi
	python3 ./scripts/import_glitch_sqlite_to_jbt.py --db "$(DB)" $(if $(REPLACE),--replace-existing,)
