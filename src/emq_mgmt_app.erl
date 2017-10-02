
-module(emq_mgmt_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    {ok, Sup} = emq_mgmt_sup:start_link(),
    emq_mgmt_http:start_listeners(),
    emq_mgmt_cli:load(),
    {ok, Sup}.

stop(_State) ->
    emq_mgmt_http:stop_listeners(),
    emq_mgmt_cli:unload().

