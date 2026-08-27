.PHONY: api-doc test

test:
	@nvim --headless -u tests/minimal_init.lua -i NONE -l tests/run.lua

api-doc:
	@command -v vimcats >/dev/null 2>&1 || { \
		echo "vimcats is not installed."; \
		echo "Install it from https://github.com/lumen-oss/vimcats"; \
		exit 1; \
	}
	@vimcats \
		lua/minibuffer/init.lua \
		lua/minibuffer/types.lua \
		lua/minibuffer/config/init.lua \
		lua/minibuffer/sessions/* \
		> doc/minibuffer.txt
	@nvim --clean -es \
		-c 'helptags doc' \
		-c 'qa'
