%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-include_lib("emqx/include/emqx.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

-define(LOG_LEVELS,["debug", "error", "info"]).
-define(LOG_HANDLER_ID, [file, default]).

all() ->
    [{group, manage_apps},
     {group, check_apps},
     {group, check_cli}].

groups() ->
    [{manage_apps, [sequence],
      [t_add_app,
       t_del_app
      ]},
     {check_apps, [sequence],
      [t_check_app,
       t_check_app_acl,
       t_log_cmd
      ]},
      {check_cli, [sequence],
       [t_log_cmd,
        t_mgmt_cmd,
        t_status_cmd,
        t_clients_cmd,
        t_sessions_cmd,
        t_vm_cmd,
        t_trace_cmd,
        t_router_cmd,
        t_subscriptions_cmd
       ]}].

init_per_suite(Config) ->
    ekka_mnesia:start(),
    emqx_mgmt_auth:mnesia(boot),
    [run_setup_steps(App) || App <- [emqx, emqx_management]],
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia),
    emqx:shutdown().

t_add_app(_Config) ->
    {ok, AppSecret} = emqx_mgmt_auth:add_app(<<"app_id">>, <<"app_name">>),
    ?assert(emqx_mgmt_auth:is_authorized(<<"app_id">>, AppSecret)),
    ?assertEqual(AppSecret, emqx_mgmt_auth:get_appsecret(<<"app_id">>)),
    ?assertEqual([{<<"app_id">>, AppSecret,
                   <<"app_name">>, <<"Application user">>,
                   true, undefined}],
                 emqx_mgmt_auth:list_apps()),
    emqx_mgmt_auth:del_app(<<"app_id">>),
    ok.

t_del_app(_Config) ->
    ok.

t_check_app(_Config) ->
    ok.

t_check_app_acl(_Config) ->
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
    [
        lists:foreach(fun(Level) ->
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
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:broker(["stats"]), "clients/count")),
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:broker(["metrice"]), "bytes/received")).

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
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:clients(["show", "client12"]), "Not Found")),
    receive
        {'EXIT', T, Reason} ->
            ct:pal("Connection closed: ~p~n", [Reason])
    after
        500 ->
            erlang:error("Client is not kick")
    end.

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
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:sessions(["show", "client2"]), "client2")).

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
    ?assertMatch({match, _}, re:run(emqx_mgmt_cli:trace(["start", "topic", "a/b/c", "log/clientid_trace.log", "error"]), "successfully")).

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
    emqx_client:connect(T3),
    emqx_client:subscribe(T3, <<"/b/b/c">>),
    [?assertMatch({match, _} , re:run(Result, "/b/b/c")) || Result <- emqx_mgmt_cli:subscriptions(["show", <<"client">>])],
    ?assertEqual(emqx_mgmt_cli:subscriptions(["add", "client", "/b/b/c", "0"]), "\"ok~n\""),
    ?assertEqual(emqx_mgmt_cli:subscriptions(["del", "client", "/b/b/c"]), "\"ok~n\"").

run_setup_steps(App) ->
    NewConfig = generate_config(App),
    lists:foreach(fun set_app_env/1, NewConfig),
                      application:ensure_all_started(App),
                      ct:log("Applications: ~p", [application:loaded_applications()]).

generate_config(emqx) ->
    Schema = cuttlefish_schema:files([local_path(["deps", "emqx", "priv", "emqx.schema"])]),
    Conf = conf_parse:file([local_path(["deps", "emqx", "etc", "emqx.conf"])]),
    cuttlefish_generator:map(Schema, Conf);

generate_config(emqx_management) ->
    Schema = cuttlefish_schema:files([local_path(["priv", "emqx_management.schema"])]),
    Conf = conf_parse:file([local_path(["etc", "emqx_management.conf"])]),
    cuttlefish_generator:map(Schema, Conf).

local_path(Components, Module) ->
    filename:join([get_base_dir(Module) | Components]).

get_base_dir(Module) ->
    {file, Here} = code:is_loaded(Module),
    filename:dirname(filename:dirname(Here)).

get_base_dir() ->
    get_base_dir(?MODULE).

local_path(Components) ->
    local_path(Components, ?MODULE).

set_app_env({App, Lists}) ->
    lists:foreach(fun({acl_file, _Var}) ->
                      application:set_env(App, acl_file, local_path(["deps", "emqx", "etc", "acl.conf"]));
                      ({plugins_loaded_file, _Var}) ->
                          application:set_env(App, plugins_loaded_file, local_path(["deps","emqx", "test", "emqx_SUITE_data", "loaded_plugins"]));
                      ({Par, Var}) ->
                          application:set_env(App, Par, Var)
                  end, Lists).
