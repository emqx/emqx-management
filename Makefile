PROJECT = emqx_management
PROJECT_DESCRIPTION = EMQ X Management API and CLI
PROJECT_VERSION = 3.0
PROJECT_MOD = emqx_mgmt_app

DEPS = minirest clique
dep_minirest = git https://github.com/emqx/minirest emqx30
dep_clique   = git https://github.com/emqx/clique

LOCAL_DEPS = mnesia

BUILD_DEPS = emqx cuttlefish
dep_emqx = git https://github.com/emqtt/emqttd emqx30
dep_cuttlefish = git https://github.com/emqtt/cuttlefish

NO_AUTOPATCH = cuttlefish

ERLC_OPTS += +debug_info

COVER = true

include erlang.mk

app.config::
	./deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emqx_management.conf -i priv/emqx_management.schema -d data
