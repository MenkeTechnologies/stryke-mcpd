SHELL := /bin/sh
.PHONY: all test install clean help

all: test

help:
	@printf '%s\n' \
	  'targets:' \
	  '  make test     - s test t/   (run the .stk tests in t/)' \
	  '  make install  - s pkg install -g .  (publish to ~/.stryke/store/utils@<ver>/)' \
	  '  make clean    - remove /tmp/stryke-mcpd-* scratch dirs'

test:
	s test t/

install:
	s pkg install -g .

clean:
	rm -rf /tmp/stryke-mcpd-*
