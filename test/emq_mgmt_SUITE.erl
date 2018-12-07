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

-module(emq_mgmt_SUITE).

-compile(export_all).

-include_lib("emqx/include/emqx.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

-import(lists, [foreach/2,zip/2]).

-define(LOG_NAMES,[debug, info, error, notice, warning, error, critical, alert, emergency]).
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
    %    t_clients_cmd,
    %    t_sessions_cmd,
       t_vm_cmd,
       t_trace_cmd]}].

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
      ct:pal("start test set primary-level log level"),
     foreach(fun(LogValues) ->
        emqx_mgmt_cli:log(["primary-level",atom_to_list(LogValues)]),  
            ?assertEqual(LogValues, emqx_logger:get_primary_log_level())
            end, ?LOG_NAMES),
         ct:pal("start test set-level log level "),
       [
        foreach(fun(LOG_NAME) ->
                    emqx_mgmt_cli:log(["handlers","set-level",atom_to_list(Id), atom_to_list(LOG_NAME)]),
                    emqx_mgmt_cli:log(["handlers", "list"])
                end,?LOG_NAMES)
                || {Id, _Level, _Dst} <- emqx_logger:get_log_handlers()].

t_mgmt_cmd(_) ->
    ct:pal("start test cases mgmt cli, test insert mgmt"),
    ct:pal("start create application"),
    emqx_mgmt_cli:mgmt(["insert", "emqx_appid", "emqx_name"]), 
    ct:pal("start lookup application"),
    emqx_mgmt_cli:mgmt(["lookup", "emqx_appid"]),
    ct:pal("application list"),
    emqx_mgmt_cli:mgmt(["list"]),
    ct:pal("application update"),
    emqx_mgmt_cli:mgmt(["update", "emqx_appid", "shutdowm"]),
    ct:pal("application delete"),
    emqx_mgmt_cli:mgmt(["delete", "emqx_appid"]),
    emqx_mgmt_cli:mgmt(["list"]).
   
t_status_cmd(_) ->
    ct:pal("start test case status cli"),
    emqx_mgmt_cli:status([]).

t_broker_cmd(_) ->
    ct:pal("start test  case broker cli"),
    emqx_mgmt_cli:broker(["stats"]),
    emqx_mgmt_cli:broker(["metrics"]).

% t_clients_cmd(_) ->
%     ct:pal("start test case client cli"),
%     {ok, T1} = emqx_client:start_link([{host, "localhost"},
%     {client_id, <<"client1">>},
%     {username, <<"testuser1">>},
%     {password, <<"pass1">>}]),
%     {ok, _} = emqx_client:connect(T1),
%     emqx_mgmt_cli:clients(["list"]),
%     emqx_mgmt_cli:clients(["show", "simpleClient"]).

% t_sessions_cmd(_) ->d
%     ct:pal("start test case session"),
%     emqx_mgmt_cli:sessions(["list"]),
%     emqx_mgmt_cli:sessions(["list", "persisent"]),
%     emqx_mgmt_cli:sessions(["list", "transient"]).

t_vm_cmd(_) ->
    {ok, Client} = emqx_client:start_link(),
    {ok, _} = emqx_client:connect(Client),
    ct:pal("start test vm"),
    emqx_mgmt_cli:vm(["all"]),
    emqx_mgmt_cli:vm(["load"]),
    emqx_mgmt_cli:vm(["memory"]),
    emqx_mgmt_cli:vm(["process"]).

t_trace_cmd(_) ->
    ct:pal("start test trace"),
    emqx_mgmt_cli:trace(["list"]).

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
