%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

-define(LOG_LEVELS,["debug", "error", "info"]).
-define(LOG_HANDLER_ID, [file, default]).

all() ->
    [{group, manage_apps},
     {group, check_cli}].

groups() ->
    [{manage_apps, [sequence],
      [t_app
      ]},
      {check_cli, [sequence],
       [t_cli,
        t_log_cmd,
        t_mgmt_cmd,
        t_status_cmd,
        t_clients_cmd,
        t_sessions_cmd,
        t_vm_cmd,
        t_plugins,
        t_trace_cmd,
        t_broker_cmd,
        t_router_cmd,
        t_subscriptions_cmd,
        t_acl,
        t_listeners
       ]}].

apps() ->
    [emqx, emqx_management, emqx_reloader].

init_per_suite(Config) ->
    ekka_mnesia:start(),
    emqx_mgmt_auth:mnesia(boot),
    emqx_ct_helpers:start_apps([emqx_management, emqx_reloader]),
    Config.

end_per_suite(_Config) ->
    emqx_ct_helpers:stop_apps([emqx_management, emqx_reloader, emqx]).

t_app(_Config) ->
    {ok, AppSecret} = emqx_mgmt_auth:add_app(<<"app_id">>, <<"app_name">>),
    ?assert(emqx_mgmt_auth:is_authorized(<<"app_id">>, AppSecret)),
    ?assertEqual(AppSecret, emqx_mgmt_auth:get_appsecret(<<"app_id">>)),
    ?assertEqual([{<<"app_id">>, AppSecret,
                   <<"app_name">>, <<"Application user">>,
                   true, undefined}],
                 emqx_mgmt_auth:list_apps()),
    emqx_mgmt_auth:del_app(<<"app_id">>),
    %% Use the default application secret
    application:set_env(emqx_management, application, [{default_secret, <<"public">>}]),
    {ok, AppSecret1} = emqx_mgmt_auth:add_app(<<"app_id">>, <<"app_name">>, <<"app_desc">>, true, undefined),
    ?assert(emqx_mgmt_auth:is_authorized(<<"app_id">>, AppSecret1)),
    ?assertEqual(AppSecret1, emqx_mgmt_auth:get_appsecret(<<"app_id">>)),
    ?assertEqual(AppSecret1, <<"public">>),
    ?assertEqual([{<<"app_id">>, AppSecret1, <<"app_name">>, <<"app_desc">>, true, undefined}], emqx_mgmt_auth:list_apps()),
    emqx_mgmt_auth:del_app(<<"app_id">>),
    application:set_env(emqx_management, application, []),
    %% Specify the application secret
    {ok, AppSecret2} = emqx_mgmt_auth:add_app(<<"app_id">>, <<"app_name">>, <<"secret">>, <<"app_desc">>, true, undefined),
    ?assert(emqx_mgmt_auth:is_authorized(<<"app_id">>, AppSecret2)),
    ?assertEqual(AppSecret2, emqx_mgmt_auth:get_appsecret(<<"app_id">>)),
    ?assertEqual([{<<"app_id">>, AppSecret2, <<"app_name">>, <<"app_desc">>, true, undefined}], emqx_mgmt_auth:list_apps()),
    emqx_mgmt_auth:del_app(<<"app_id">>),
    ok.

t_log_cmd(_) ->
    lists:foreach(fun(Level) ->
                      emqx_mgmt_cli:log(["primary-level", Level]),
                      ?assertEqual(Level++"\n", emqx_mgmt_cli:log(["primary-level"]))
                  end, ?LOG_LEVELS),
    lists:foreach(fun(Level) ->
                     emqx_mgmt_cli:log(["set-level", Level]),
                     ?assertEqual(Level++"\n", emqx_mgmt_cli:log(["primary-level"]))
                  end, ?LOG_LEVELS),
    [lists:foreach(fun(Level) ->
                         ?assertEqual(Level++"\n", emqx_mgmt_cli:log(["handlers", "set-level",
                                                                      atom_to_list(Id), Level]))
                      end, ?LOG_LEVELS)
        || {Id, _Level, _Dst} <- emqx_logger:get_log_handlers()].

t_mgmt_cmd(_) ->
    ct:pal("start testing the mgmt command"),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:mgmt(["insert", "emqx_appid", "emqx_name"]), "AppSecret:")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:mgmt(["lookup", "emqx_appid"]), "app_id:")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:mgmt(["update", "emqx_appid", "ts"]), "update successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:mgmt(["delete", "emqx_appid"]), "ok")).

t_status_cmd(_) ->
    ct:pal("start testing status command"),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:status([]), "is running")).

t_broker_cmd(_) ->
    ct:pal("start testing the broker command"),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:broker(["stats"]), "subscriptions.shared")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:broker(["metrice"]), "broker")).

t_clients_cmd(_) ->
    ct:pal("start testing the client command"),
    process_flag(trap_exit, true),
    {ok, T} = emqx_client:start_link([{host, "localhost"},
                                      {client_id, <<"client12">>},
                                      {username, <<"testuser1">>},
                                      {password, <<"pass1">>}]),
    {ok, _} = emqx_client:connect(T),
    emqx_mgmt_cli:clients(["list"]),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:clients(["show", "client12"]), "client12")),
    emqx_mgmt_cli:clients(["kick", "client12"]),
    timer:sleep(500),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:clients(["show", "client12"]), "Not Found")),
    receive
        {'EXIT', T, Reason} ->
            ct:pal("Connection closed: ~p~n", [Reason])
    after
        500 ->
            erlang:error("Client is not kick")
    end,
    WS = rfc6455_client:new("ws://127.0.0.1:8083" ++ "/mqtt", self()),
    {ok, _} = rfc6455_client:open(WS),
    Packet = raw_send_serialize(?CONNECT_PACKET(#mqtt_packet_connect{
                                                   client_id = <<"client13">>})),
    ok = rfc6455_client:send_binary(WS, Packet),
    Connack = ?CONNACK_PACKET(?CONNACK_ACCEPT),
    {binary, Bin} = rfc6455_client:recv(WS),
    {ok, Connack, <<>>, _} = raw_recv_pase(Bin),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:clients(["show", "client13"]), "client13")),
    emqx_mgmt_cli:clients(["kick", "client13"]),
    timer:sleep(500),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:clients(["show", "client13"]), "Not Found")).

raw_recv_pase(Packet) ->
    emqx_frame:parse(Packet).

raw_send_serialize(Packet) ->
    emqx_frame:serialize(Packet).

t_sessions_cmd(_) ->
    ct:pal("start testing the session command"),
    {ok, T1} = emqx_client:start_link([{host, "localhost"},
                                       {client_id, <<"client1">>},
                                       {username, <<"testuser1">>},
                                       {password, <<"pass1">>},
                                       {clean_start, false}]),
    {ok, _} = emqx_client:connect(T1),
    {ok, T2} = emqx_client:start_link([{host, "localhost"},
                                       {client_id, <<"client2">>},
                                       {username, <<"testuser2">>},
                                       {password, <<"pass2">>},
                                       {clean_start, true}]),
    {ok, _} = emqx_client:connect(T2),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:sessions(["list"]), "Session")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:sessions(["show", "client2"]), "client2")),
    ok = emqx_client:disconnect(T1),
    ok = emqx_client:disconnect(T2),
    timer:sleep(100),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:sessions(["clean-persistent", "client1"]), "successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:sessions(["clean-persistent", "client2"]), "Not Found")).


t_vm_cmd(_) ->
    ct:pal("start testing the vm command"),
    [[?assertMatch({match, _}, re:run(Result, Name)) || Result <- emqx_mgmt_cli:vm([Name])] || Name <- ["load", "memory", "process", "io", "ports"]],
    [?assertMatch({match, _}, re:run(Result, "load")) || Result <- emqx_mgmt_cli:vm(["load"])],
    [?assertMatch({match, _}, re:run(Result, "memory"))|| Result <- emqx_mgmt_cli:vm(["memory"])],
    [?assertMatch({match, _}, re:run(Result, "process")) || Result <- emqx_mgmt_cli:vm(["process"])],
    [?assertMatch({match, _}, re:run(Result, "io")) || Result <- emqx_mgmt_cli:vm(["io"])],
    [?assertMatch({match, _}, re:run(Result, "ports")) || Result <- emqx_mgmt_cli:vm(["ports"])].

t_trace_cmd(_) ->
    ct:pal("start testing the trace command"),
    logger:set_primary_config(level, debug),
    {ok, T} = emqx_client:start_link([{host, "localhost"},
                                      {client_id, <<"client">>},
                                      {username, <<"testuser">>},
                                      {password, <<"pass">>}]),
    emqx_client:connect(T),
    emqx_client:subscribe(T, <<"a/b/c">>),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["start", "client", "client", "log/clientid_trace.log"]), "successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["stop", "client", "client"]), "successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["start", "client", "client", "log/clientid_trace.log", "error"]), "successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["stop", "client", "client"]), "successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["start", "topic", "a/b/c", "log/clientid_trace.log"]), "successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["stop", "topic", "a/b/c"]), "successfully")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["start", "topic", "a/b/c", "log/clientid_trace.log", "error"]), "successfully")),
    logger:set_primary_config(level, error).

t_router_cmd(_) ->
    ct:pal("start testing the router command"),
    {ok, T} = emqx_client:start_link([{host, "localhost"},
                                      {client_id, <<"client1">>},
                                      {username, <<"testuser1">>},
                                      {password, <<"pass1">>}]),
    emqx_client:connect(T),
    emqx_client:subscribe(T, <<"a/b/c">>),
    {ok, T1} = emqx_client:start_link([{host, "localhost"},
                                       {client_id, <<"client2">>},
                                       {username, <<"testuser2">>},
                                       {password, <<"pass2">>}]),
    emqx_client:connect(T1),
    emqx_client:subscribe(T1, <<"a/b/c/d">>),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:routes(["list"]), "a/b/c | a/b/c")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:routes(["show", "a/b/c"]), "a/b/c")).

t_subscriptions_cmd(_) ->
    ct:pal("Start testing the subscriptions command"),
    {ok, T3} = emqx_client:start_link([{host, "localhost"},
                                       {client_id, <<"client">>},
                                       {username, <<"testuser">>},
                                       {password, <<"pass">>}]),
    {ok, _} = emqx_client:connect(T3),
    {ok, _, _} = emqx_client:subscribe(T3, <<"b/b/c">>),
    timer:sleep(300),
    [?assertMatch({match, _} , re:run(Result, "b/b/c"))
     || Result <- emqx_mgmt_cli:subscriptions(["show", <<"client">>])],
    ?assertEqual(emqx_mgmt_cli:subscriptions(["add", "client", "b/b/c", "0"]), "\"ok~n\""),
    ?assertEqual(emqx_mgmt_cli:subscriptions(["del", "client", "b/b/c"]), "\"ok~n\"").

t_listeners(_) ->
    ?assertEqual(emqx_mgmt_cli:listeners([]), ok),
    ?assertEqual(emqx_mgmt_cli:listeners(["stop", "mqtt:wss", "8084"]), "Stop mqtt:wss listener on 8084 successfully.\n").

t_acl(_) ->
    ct:pal("Start testing the acl command"),
    ?assertEqual(emqx_mgmt_cli:acl(["reload"]), ok).

t_plugins(_) ->
    ?assertEqual(emqx_mgmt_cli:plugins(["list"]), ok),
    ?assertEqual(emqx_mgmt_cli:plugins(["unload", "emqx_reloader"]), "Plugin emqx_reloader unloaded successfully.\n"),
    ?assertEqual(emqx_mgmt_cli:plugins(["load", "emqx_reloader"]),"Start apps: [emqx_reloader]\nPlugin emqx_reloader loaded successfully.\n"),
    ?assertEqual(emqx_mgmt_cli:plugins(["unload", "emqx_management"]), "\"Plugin emqx_management can not be unloaded ~n\"").

t_cli(_) ->
    [?assertMatch({match, _}, re:run(Value, "status")) || Value <- emqx_mgmt_cli:status([""])],
    [?assertMatch({match, _}, re:run(Value, "broker")) || Value <- emqx_mgmt_cli:broker([""])],
    [?assertMatch({match, _}, re:run(Value, "cluster")) || Value <- emqx_mgmt_cli:cluster([""])],
    [?assertMatch({match, _}, re:run(Value, "clients")) || Value <- emqx_mgmt_cli:clients([""])],
    [?assertMatch({match, _}, re:run(Value, "sessions")) || Value <- emqx_mgmt_cli:sessions([""])],
    [?assertMatch({match, _}, re:run(Value, "routes")) || Value <- emqx_mgmt_cli:routes([""])],
    [?assertMatch({match, _}, re:run(Value, "subscriptions")) || Value <- emqx_mgmt_cli:subscriptions([""])],
    [?assertMatch({match, _}, re:run(Value, "plugins")) || Value <- emqx_mgmt_cli:plugins([""])],
    [?assertMatch({match, _}, re:run(Value, "listeners")) || Value <- emqx_mgmt_cli:listeners([""])],
    [?assertMatch({match, _}, re:run(Value, "vm")) || Value <- emqx_mgmt_cli:vm([""])],
    [?assertMatch({match, _}, re:run(Value, "mnesia")) || Value <- emqx_mgmt_cli:mnesia([""])],
    [?assertMatch({match, _}, re:run(Value, "trace")) || Value <- emqx_mgmt_cli:trace([""])],
    [?assertMatch({match, _}, re:run(Value, "acl")) || Value <- emqx_mgmt_cli:acl([""])],
    [?assertMatch({match, _}, re:run(Value, "mgmt")) || Value <- emqx_mgmt_cli:mgmt([""])].
