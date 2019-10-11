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

-module(emqx_mgmt_api_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").

-define(CONTENT_TYPE, "application/x-www-form-urlencoded").

-define(HOST, "http://127.0.0.1:8080/").

-define(API_VERSION, "v3").

-define(BASE_PATH, "api").

all() ->
    [{group, rest_api}].

groups() ->
    [{rest_api,
      [sequence],
      [alarms,
       apps,
       banned,
       brokers,
       configs,
       connections_and_sessions,
       connections_and_sessions_2,
       listeners,
       metrics,
       nodes,
       plugins,
       pubsub,
       routes_and_subscriptions,
       stats]}].

init_per_suite(Config) ->
    emqx_ct_helpers:start_apps([emqx, emqx_management, emqx_reloader]),
    ekka_mnesia:start(),
    emqx_mgmt_auth:mnesia(boot),
    emqx_mgmt_auth:add_app(<<"myappid">>, <<"test">>),
    Config.

end_per_suite(_Config) ->
    emqx_ct_helpers:stop_apps([emqx_reloader, emqx_management, emqx]),
    ekka_mnesia:ensure_stopped().

get(data, ResponseBody) ->
    proplists:get_value(<<"data">>, jsx:decode(list_to_binary(ResponseBody)));
get(meta, ResponseBody) ->
    proplists:get_value(<<"meta">>, jsx:decode(list_to_binary(ResponseBody))).

alarms(_) ->
    AlarmTest = #alarm{id = <<"1">>, severity = error, title="alarm title", summary="alarm summary"},
    alarm_handler:set_alarm({<<"1">>, AlarmTest}),
    timer:sleep(100),
    [{_AlarmId, AlarmDesc}] = emqx_alarm_handler:get_alarms(),
    ?assertEqual(error, AlarmDesc#alarm.severity),
    {ok, _} = request_api(get, api_path(["alarms/present"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["alarms/present", atom_to_list(node())]), auth_header_()),
    {ok, _} = request_api(get, api_path(["alarms/history"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["alarms/history", atom_to_list(node())]), auth_header_()).

apps(_) ->
    AppId = <<"123456">>,
    {ok, _} = request_api(post, api_path(["apps"]), [],
                          auth_header_(), [{<<"app_id">>, AppId},
                                           {<<"name">>,   <<"test">>},
                                           {<<"status">>, true}]),

    {ok, _} = request_api(get, api_path(["apps"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["apps", binary_to_list(AppId)]), auth_header_()),
    {ok, _} = request_api(put, api_path(["apps", binary_to_list(AppId)]), [],
                          auth_header_(), [{<<"name">>, <<"test 2">>},
                                           {<<"status">>, true}]),
    {ok, AppInfo} = request_api(get, api_path(["apps", binary_to_list(AppId)]), auth_header_()),
    ?assertEqual(<<"test 2">>, proplists:get_value(<<"name">>, get(data, AppInfo))),
    {ok, _} = request_api(delete, api_path(["apps", binary_to_list(AppId)]), auth_header_()),
    {ok, Result} = request_api(get, api_path(["apps"]), auth_header_()),
    [App] = get(data, Result),
    ?assertEqual(<<"myappid">>, proplists:get_value(<<"app_id">>, App)).

banned(_) ->
    Who = <<"myclient">>,
    {ok, _} = request_api(post, api_path(["banned"]), [],
                          auth_header_(), [{<<"who">>, Who},
                                           {<<"as">>, <<"client_id">>},
                                           {<<"reason">>, <<"test">>},
                                           {<<"by">>, <<"dashboard">>},
                                           {<<"desc">>, <<"hello world">>},
                                           {<<"until">>, erlang:system_time(second) + 10}]),

    {ok, Result} = request_api(get, api_path(["banned"]), auth_header_()),
    [Banned] = get(data, Result),
    ?assertEqual(Who, proplists:get_value(<<"who">>, Banned)),

    {ok, _} = request_api(delete, api_path(["banned", binary_to_list(Who)]), [],
                          auth_header_(), [{<<"as">>, <<"client_id">>}]),
    {ok, Result2} = request_api(get, api_path(["banned"]), auth_header_()),
    ?assertEqual([], get(data, Result2)).

brokers(_) ->
    {ok, _} = request_api(get, api_path(["brokers"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["brokers", atom_to_list(node())]), auth_header_()).

configs(_) ->
    {ok, _} = request_api(get, api_path(["configs"]), auth_header_()),

    {ok, _} = request_api(get, api_path(["nodes", atom_to_list(node()), "configs"]), auth_header_()),

    {ok, _} = request_api(put, api_path(["nodes", atom_to_list(node()), "plugin_configs", atom_to_list(emqx_reloader)]), [],
                          auth_header_(), [{<<"reloader.interval">>, <<"60s">>},
                                           {<<"reloader.logfile">>, <<"reloader.log">>}]),

    {ok, Result} = request_api(get, api_path(["nodes", atom_to_list(node()), "plugin_configs", atom_to_list(emqx_reloader)]),
                               auth_header_()),
    ?assert(lists:any(fun(Elem) ->
                              case proplists:get_value(<<"key">>, Elem) of
                              <<"reloader.interval">> ->
                                  <<"60s">> == proplists:get_value(<<"value">>, Elem);
                              _ -> false
                          end
                      end, get(data, Result))).

connections_and_sessions(_) ->
    process_flag(trap_exit, true),
    Username = <<"Gilbert">>,
    Options = #{username => Username},
    ClientId1 = <<"client1">>,
    ClientId2 = <<"client2">>,
    {ok, C1} = emqx_client:start_link(Options#{client_id => ClientId1}),
    {ok, _} = emqx_client:connect(C1),
    {ok, C2} = emqx_client:start_link(Options#{client_id => ClientId2}),
    {ok, _} = emqx_client:connect(C2),

    {ok, ConsViaUsername} = request_api(get, api_path(["nodes", atom_to_list(node()),
                                                      "connection",
                                                      "username", binary_to_list(Username)])
                                      , auth_header_()),
    ?assertEqual(2, length(get(data, ConsViaUsername))),
    {ok, Conns} = request_api(get, api_path(["connections"]), "_limit=100&_page=1",
                              auth_header_()),
    ?assertEqual(2, proplists:get_value(<<"count">>, get(meta, Conns))),
    {ok, Conns} = request_api(get, api_path(["nodes", atom_to_list(node()), "connections"]), "_limit=100&_page=1",
                              auth_header_()),
    {ok, Result} = request_api(get, api_path(["nodes", atom_to_list(node()), "connections", binary_to_list(ClientId1)]), auth_header_()),
    [Conn] = get(data, Result),
    ?assertEqual(ClientId1, proplists:get_value(<<"client_id">>, Conn)),

    {ok, Result} = request_api(get, api_path(["connections",
                                              binary_to_list(ClientId1)]),
                               auth_header_()),

    {ok, Result2} = request_api(get, api_path(["sessions"]), auth_header_()),
    [Session1, Session2] = get(data, Result2),
    ?assertEqual(ClientId1, proplists:get_value(<<"client_id">>, Session1)),
    ?assertEqual(ClientId2, proplists:get_value(<<"client_id">>, Session2)),
    {ok, Result2} = request_api(get, api_path(["nodes", atom_to_list(node()), "sessions"]), auth_header_()),

    {ok, Result3} = request_api(get, api_path(["sessions", binary_to_list(ClientId1)]), auth_header_()),
    {ok, Result3} = request_api(get, api_path(["nodes", atom_to_list(node()),
                                               "sessions", binary_to_list(ClientId1)]),
                                auth_header_()),

    {ok, _} = request_api(delete, api_path(["connections", binary_to_list(ClientId1)]), auth_header_()),
    {ok, _} = request_api(delete, api_path(["connections", binary_to_list(ClientId2)]), auth_header_()),
    receive_exit(2),
    {ok, NonConn} = request_api(
                      get, api_path(["connections"]), "_limit=100&_page=1", auth_header_()),
    ?assertEqual([], get(data, NonConn)),
    {ok, NonSession} = request_api(get, api_path(["sessions"]), auth_header_()),
    ?assertEqual([], get(data, NonSession)).

connections_and_sessions_2(_) ->
    process_flag(trap_exit, true),
    ClientId1 = <<"client1">>,
    ClientId2 = <<"client2">>,
    {ok, C1} = emqx_client:start_link(#{client_id => ClientId1, clean_start => false}),
    {ok, C2} = emqx_client:start_link(#{client_id => ClientId2, clean_start => false}),
    {ok, _} = emqx_client:connect(C1),
    {ok, _} = emqx_client:connect(C2),

    {ok, Result1} = request_api(get, api_path(["sessions"]), auth_header_()),
    emqx_client:disconnect(C1),
    emqx_client:disconnect(C2),
    {ok, Result1} = request_api(get, api_path(["sessions"]), auth_header_()),
    {ok, Result2} = request_api(delete, api_path(["sessions", "persistent", binary_to_list(ClientId1)]), auth_header_()),
    {ok, Result2} = request_api(delete, api_path(["nodes", atom_to_list(node()),
                                                  "sessions", "persistent", binary_to_list(ClientId2)]), auth_header_()),
    ?assertEqual(0, proplists:get_value(<<"code">>, jsx:decode(list_to_binary(Result2)))),
    {ok, Result3} = request_api(get, api_path(["sessions"]), auth_header_()),
    ?assertEqual([], get(data, Result3)).

receive_exit(0) ->
    ok;
receive_exit(Count) ->
    receive
        {'EXIT', Client, {shutdown, tcp_closed}} ->
            ct:log("receive exit signal, Client: ~p", [Client]),
            receive_exit(Count - 1);
        {'EXIT', Client, _Reason} ->
            ct:log("receive exit signal, Client: ~p", [Client]),
            receive_exit(Count - 1)
    after 1000 ->
            ct:log("timeout")
    end.

listeners(_) ->
    {ok, _} = request_api(get, api_path(["listeners"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", atom_to_list(node()), "listeners"]), auth_header_()).

metrics(_) ->
    {ok, _} = request_api(get, api_path(["metrics"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", atom_to_list(node()), "metrics"]), auth_header_()).

nodes(_) ->
    {ok, _} = request_api(get, api_path(["nodes"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", atom_to_list(node())]), auth_header_()).

plugins(_) ->
    {ok, _} = request_api(put, api_path([ "nodes", atom_to_list(node()), "plugins", atom_to_list(emqx_reloader), "unload"]),
                          auth_header_()),

    {ok, Result3} = request_api(get, api_path([ "nodes", atom_to_list(node()), "plugins"]),
                                auth_header_()),
    [Plugin3] = filter(get(data, Result3), <<"emqx_reloader">>),
    ?assertEqual(<<"emqx_reloader">>, proplists:get_value(<<"name">>, Plugin3)),
    ?assertNot(proplists:get_value(<<"active">>, Plugin3)),
    {ok, _} = request_api(put, api_path([ "nodes", atom_to_list(node()), "plugins", atom_to_list(emqx_reloader), "load"]),
                          auth_header_()),
    {ok, Result} = request_api(get, api_path(["plugins"]), auth_header_()),
    [Plugins] = get(data, Result),
    [Plugin] = filter(proplists:get_value(<<"plugins">>, Plugins), <<"emqx_reloader">>),
    ?assertEqual(<<"emqx_reloader">>, proplists:get_value(<<"name">>, Plugin)),
    ?assert(proplists:get_value(<<"active">>, Plugin)),
    {ok, Result2} = request_api(get, api_path([ "nodes", atom_to_list(node()), "plugins"]), auth_header_()),
    [Plugin] = filter(get(data, Result2), <<"emqx_reloader">>).

pubsub(_) ->
    ClientId = <<"client1">>,
    Options = #{client_id => ClientId,
                proto_ver => 5},
    Topic = <<"mytopic">>,
    {ok, C1} = emqx_client:start_link(Options),
    {ok, _} = emqx_client:connect(C1),
    {ok, _, [2]} = emqx_client:subscribe(C1, Topic, 2),
    {ok, Code} = request_api(post, api_path(["mqtt/subscribe"]), [], auth_header_(),
                             [{<<"client_id">>, ClientId},
                              {<<"topic">>, Topic},
                              {<<"qos">>, 2}]),
    ?assertEqual(0, proplists:get_value(<<"code">>, jsx:decode(list_to_binary(Code)))),
    {ok, Code} = request_api(post, api_path(["mqtt/publish"]), [], auth_header_(),
                             [{<<"client_id">>, ClientId},
                              {<<"topic">>, <<"mytopic">>},
                              {<<"qos">>, 1},
                              {<<"payload">>, <<"hello">>}]),
    ?assert(receive
                {publish, #{payload := <<"hello">>}} ->
                    true
            after 100 ->
                    false
            end),
    {ok, Code} = request_api(post, api_path(["mqtt/unsubscribe"]), [], auth_header_(),
                             [{<<"client_id">>, ClientId},
                              {<<"topic">>, Topic}]),

    %% tests subscribe_batch
    TopicList = [<<"mytopic1">>, <<"mytopic2">>],
    [emqx_client:subscribe(C1, Topic1, 2) || Topic1 <- TopicList],

    Body1 = [[{<<"client_id">>, ClientId}, {<<"topic">>, Topics}, {<<"qos">>, 2}] || Topics <- TopicList],
    {ok, Data1} = request_api(post, api_path(["mqtt/subscribe_batch"]), [], auth_header_(),Body1),
    loop(proplists:get_value(<<"data">>, jsx:decode(list_to_binary(Data1)))),

    %% tests publish_batch
    Body2 = [ [{<<"client_id">>, ClientId},
               {<<"topic">>, Topic1},
               {<<"qos">>, 2},
               {<<"retain">>, <<"false">>},
               {<<"payload">>, <<"publish_batch">>}] || Topic1 <- TopicList ],
    {ok, Data2} = request_api(post, api_path(["mqtt/publish_batch"]), [], auth_header_(),Body2),
    loop(proplists:get_value(<<"data">>, jsx:decode(list_to_binary(Data2)))),
    [ ?assert(receive
                    {publish, #{topic := Topics}} ->
                        true
                    after 100 ->
                        false
                    end) || Topics <- TopicList ],

    %% tests unsubscribe_batch
    Body3 = [[{<<"client_id">>, ClientId}, {<<"topic">>, Topic1}] || Topic1 <- TopicList],
    {ok, Data3} = request_api(post, api_path(["mqtt/unsubscribe_batch"]), [], auth_header_(),Body3),
    loop(proplists:get_value(<<"data">>, jsx:decode(list_to_binary(Data3)))).

loop([]) -> [];

loop(Data) ->
    [Resp | Resps] = Data,
    ct:pal("Resp: ~p~n", [Resp]),
    ?assertEqual(0, proplists:get_value(<<"code">>, Resp)),
    loop(Resps).

routes_and_subscriptions(_) ->
    {ok, NonRoute} = request_api(get, api_path(["routes"]), auth_header_()),
    ?assertEqual([], get(data, NonRoute)),
    ClientId = <<"myclient">>,
    Options = #{client_id => <<"myclient">>},
    Topic = <<"mytopic">>,
    {ok, C1} = emqx_client:start_link(Options#{clean_start => true,
                                               client_id   => ClientId,
                                               proto_ver   => ?MQTT_PROTO_V5}),
    {ok, _} = emqx_client:connect(C1),
    {ok, _, [2]} = emqx_client:subscribe(C1, Topic, qos2),
    {ok, Result} = request_api(get, api_path(["routes"]), auth_header_()),
    [Route] = get(data, Result),
    ?assertEqual(Topic, proplists:get_value(<<"topic">>, Route)),

    {ok, Result2} = request_api(get, api_path(["routes", binary_to_list(Topic)]), auth_header_()),
    [Route] = get(data, Result2),

    {ok, Result3} = request_api(get, api_path(["subscriptions"]), auth_header_()),
    [Subscription] = get(data, Result3),
    ?assertEqual(Topic, proplists:get_value(<<"topic">>, Subscription)),
    ?assertEqual(ClientId, proplists:get_value(<<"client_id">>, Subscription)),

    {ok, Result3} = request_api(get, api_path(["nodes", atom_to_list(node()), "subscriptions"]), auth_header_()),

    {ok, Result4} = request_api(get, api_path(["subscriptions", binary_to_list(ClientId)]), auth_header_()),
    [Subscription] = get(data, Result4),
    {ok, Result4} = request_api(get, api_path(["nodes", atom_to_list(node()), "subscriptions", binary_to_list(ClientId)])
                               , auth_header_()).

stats(_) ->
    {ok, _} = request_api(get, api_path(["stats"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", atom_to_list(node()), "stats"]), auth_header_()).

request_api(Method, Url, Auth) ->
    request_api(Method, Url, [], Auth, []).

request_api(Method, Url, QueryParams, Auth) ->
    request_api(Method, Url, QueryParams, Auth, []).

request_api(Method, Url, [], Auth, []) ->
    do_request_api(Method, {Url, [Auth]});
request_api(Method, Url, QueryParams, Auth, []) ->
    NewUrl = Url ++ "?" ++ QueryParams,
    do_request_api(Method, {NewUrl, [Auth]});
request_api(Method, Url, QueryParams, Auth, Body) ->
    NewUrl = Url ++ "?" ++ QueryParams,
    do_request_api(Method, {NewUrl, [Auth], "application/json", emqx_json:encode(Body)}).

do_request_api(Method, Request)->
    ct:pal("Method: ~p, Request: ~p", [Method, Request]),
    case httpc:request(Method, Request, [], []) of
        {error, socket_closed_remotely} ->
            {error, socket_closed_remotely};
        {ok, {{"HTTP/1.1", Code, _}, _, Return} }
            when Code =:= 200 orelse Code =:= 201 ->
            {ok, Return};
        {ok, {Reason, _, _}} ->
            {error, Reason}
    end.

auth_header_() ->
    AppId = <<"myappid">>,
    AppSecret = emqx_mgmt_auth:get_appsecret(AppId),
    auth_header_(binary_to_list(AppId), binary_to_list(AppSecret)).

auth_header_(User, Pass) ->
    Encoded = base64:encode_to_string(lists:append([User,":",Pass])),
    {"Authorization","Basic " ++ Encoded}.

api_path(Parts)->
    ?HOST ++ filename:join([?BASE_PATH, ?API_VERSION] ++ Parts).

filter(List, Name) ->
    lists:filter(fun(Item) ->
        proplists:get_value(<<"name">>, Item) == Name
    end, List).
