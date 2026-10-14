# makefile
RMLIBFILES = lib/msgpack/Guardfile lib/msgpack/CHANGELOG.md lib/msgpack/.travis.yml lib/msgpack/.gitignore \
             lib/msgpack/spec lib/msgpack/examples lib/msgpack/bench lib/msgpack/.github lib/msgpack/lib
						 
.PHONY: all shards clean spec help

all: spec

shard.lock:
	shards install
	@rm -rf $(RMLIBFILES)

shards: clean       ## Install shards
	shards install
	@rm -rf $(RMLIBFILES)

clean:              ## Remove /lib and  shard.lock
	rm -rf lib
	rm -f shard.lock

spec: shard.lock    ## Run spec suite
	crystal spec

help:               ## Show this help text
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-18s %s\n", $$1, $$2}'