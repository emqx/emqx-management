PROJECT = emqx_management
PROJECT_DESCRIPTION = EMQ X Management API and CLI
PROJECT_MOD = emqx_mgmt_app

DEPS = minirest clique
dep_minirest = git-emqx https://github.com/emqx/minirest v0.2.0
dep_clique   = git-emqx https://github.com/emqx/clique v0.3.11

LOCAL_DEPS = mnesia

CUR_BRANCH := $(shell git branch | grep -e "^*" | cut -d' ' -f 2)
BRANCH := $(if $(filter $(CUR_BRANCH), master develop), $(CUR_BRANCH))

BUILD_DEPS = emqx cuttlefish
dep_emqx = git-emqx https://github.com/emqx/emqx $(BRANCH)
dep_cuttlefish = git-emqx https://github.com/emqx/cuttlefish v2.2.1

TEST_DEPS = emqx_reloader
dep_emqx_reloader = git-emqx https://github.com/emqx/emqx-reloader $(BRANCH)

NO_AUTOPATCH = cuttlefish

ERLC_OPTS += +debug_info

COVER = true

$(shell [ -f erlang.mk ] || curl -s -o erlang.mk https://raw.githubusercontent.com/emqx/erlmk/master/erlang.mk)
include erlang.mk

CUTTLEFISH_SCRIPT = _build/default/lib/cuttlefish/cuttlefish

app.config: $(CUTTLEFISH_SCRIPT) etc/emqx_management.conf
	$(verbose) $(CUTTLEFISH_SCRIPT) -l info -e etc/ -c etc/emqx_management.conf -i priv/emqx_management.schema -d data

$(CUTTLEFISH_SCRIPT): rebar-deps
	@if [ ! -f cuttlefish ]; then make -C _build/default/lib/cuttlefish; fi

distclean::
	@rm -rf _build cover deps logs log data
	@rm -f rebar.lock compile_commands.json cuttlefish

rebar-deps:
	rebar3 get-deps

rebar-clean:
	@rebar3 clean

rebar-compile: rebar-deps
	rebar3 compile

rebar-ct: app.config
	rebar3 ct

rebar-eunit: $(CUTTLEFISH_SCRIPT)
	@rebar3 eunit

rebar-xref:
	@rebar3 xref
