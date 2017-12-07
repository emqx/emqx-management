%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_mgmt_config_SUITE).

-compile(export_all).

-include("emqx.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

all() ->
    [{group, cli}].

groups() ->
    [{cli, [sequence],
      [ctl_register_cmd,
       cli_status,
       cli_broker,
       cli_clients,
       cli_sessions,
       cli_routes,
       cli_topics,
       cli_subscriptions,
       cli_bridges,
       cli_plugins,
       {listeners, [sequence],
        [cli_listeners,
         conflict_listeners
         ]},
       cli_vm]}].

cli_status(_) ->
    emqx_mgmt_cli:status([]).

cli_broker(_) ->
    emqx_mgmt_cli:broker([]),
    emqx_mgmt_cli:broker(["stats"]),
    emqx_mgmt_cli:broker(["metrics"]),
    emqx_mgmt_cli:broker(["pubsub"]).

cli_clients(_) ->
    emqx_mgmt_cli:clients(["list"]),
    emqx_mgmt_cli:clients(["show", "clientId"]),
    emqx_mgmt_cli:clients(["kick", "clientId"]).

cli_sessions(_) ->
    emqx_mgmt_cli:sessions(["list"]),
    emqx_mgmt_cli:sessions(["list", "persistent"]),
    emqx_mgmt_cli:sessions(["list", "transient"]),
    emqx_mgmt_cli:sessions(["show", "clientId"]).

cli_routes(_) ->
    emqx:subscribe(<<"topic/route">>),
    emqx_mgmt_cli:routes(["list"]),
    emqx_mgmt_cli:routes(["show", "topic/route"]),
    emqx:unsubscribe(<<"topic/route">>).

cli_topics(_) ->
    emqx:subscribe(<<"topic">>),
    emqx_mgmt_cli:topics(["list"]),
    emqx_mgmt_cli:topics(["show", "topic"]),
    emqx:unsubscribe(<<"topic">>).

cli_subscriptions(_) ->
    emqx_mgmt_cli:subscriptions(["list"]),
    emqx_mgmt_cli:subscriptions(["show", "clientId"]),
    emqx_mgmt_cli:subscriptions(["add", "clientId", "topic", "2"]),
    emqx_mgmt_cli:subscriptions(["del", "clientId", "topic"]).

cli_plugins(_) ->
    emqx_mgmt_cli:plugins(["list"]),
    emqx_mgmt_cli:plugins(["load", "emqx_plugin_template"]),
    emqx_mgmt_cli:plugins(["unload", "emqx_plugin_template"]).

cli_bridges(_) ->
    emqx_mgmt_cli:bridges(["list"]),
    emqx_mgmt_cli:bridges(["start", "a@127.0.0.1", "topic"]),
    emqx_mgmt_cli:bridges(["stop", "a@127.0.0.1", "topic"]).

cli_listeners(_) ->
    emqx_mgmt_cli:listeners([]).

conflict_listeners(_) ->
    F =
    fun() ->
    process_flag(trap_exit, true),
    emqttc:start_link([{host, "localhost"},
                       {port, 1883},
                       {client_id, <<"c1">>},
                       {clean_sess, false}])
    end,
    spawn_link(F),

    {ok, C2} = emqttc:start_link([{host, "localhost"},
                                  {port, 1883},
                                  {client_id, <<"c1">>},
                                  {clean_sess, false}]),
    timer:sleep(100),

    Listeners =
    lists:map(fun({{Protocol, ListenOn}, Pid}) ->
        Key = atom_to_list(Protocol) ++ ":" ++ esockd:to_string(ListenOn),
        {Key, [{acceptors, esockd:get_acceptors(Pid)},
               {max_clients, esockd:get_max_clients(Pid)},
               {current_clients, esockd:get_current_clients(Pid)},
               {shutdown_count, esockd:get_shutdown_count(Pid)}]}
              end, esockd:listeners()),
    L = proplists:get_value("mqtt:tcp:0.0.0.0:1883", Listeners),
    ?assertEqual(1, proplists:get_value(current_clients, L)),
    ?assertEqual(1, proplists:get_value(conflict, proplists:get_value(shutdown_count, L))),
    timer:sleep(100),
    emqttc:disconnect(C2).

cli_vm(_) ->
    emqx_mgmt_cli:vm([]),
    emqx_mgmt_cli:vm(["ports"]).
