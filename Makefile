.PHONY: up down status logs tabs run demo package

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
