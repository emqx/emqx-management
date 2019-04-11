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

batch_connect(NumberOfConnections) ->
    batch_connect([], NumberOfConnections).

batch_connect(Socks, 0) ->
    Socks;
batch_connect(Socks, NumberOfConnections) ->
    {ok, Sock} = emqx_client_sock:connect({127, 0, 0, 1}, 1883,
                                          [binary, {packet, raw}, {active, false}], 
                                          3000),
    batch_connect([Sock | Socks], NumberOfConnections - 1).

with_connection(DoFun, NumberOfConnections) ->
    Socks = batch_connect(NumberOfConnections),
    try
        DoFun(Socks)
    after
        lists:foreach(fun(Sock) ->
                         emqx_client_sock:close(Sock) 
                      end, Socks)
    end.

with_connection(DoFun) ->
    with_connection(DoFun, 1).

get(data, ResponseBody) ->
    proplists:get_value(<<"data">>, jsx:decode(list_to_binary(ResponseBody)));
get(meta, ResponseBody) ->
    proplists:get_value(<<"meta">>, jsx:decode(list_to_binary(ResponseBody))).

alarms(_) ->
    AlarmTest = #alarm{id = <<"1">>, severity = error, title="alarm title", summary="alarm summary"},
    alarm_handler:set_alarm({<<"1">>, AlarmTest}),
    [{_AlarmId, AlarmDesc}] = emqx_alarm_handler:get_alarms(),
    ?assertEqual(error, AlarmDesc#alarm.severity),
    {ok, _} = request_api(get, api_path(["alarms"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["alarms", erlang:atom_to_list(node())]), auth_header_()).

apps(_) ->
    AppId = <<"123456">>,
    {ok, _} = request_api(post, api_path(["apps"]), [], 
                          auth_header_(), [{<<"app_id">>, AppId},
                                           {<<"name">>,   <<"test">>},
                                           {<<"status">>, true}]),

    {ok, _} = request_api(get, api_path(["apps"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["apps", erlang:binary_to_list(AppId)]), auth_header_()),
    {ok, _} = request_api(put, api_path(["apps", erlang:binary_to_list(AppId)]), [],
                          auth_header_(), [{<<"name">>, <<"test 2">>},
                                           {<<"status">>, true}]),
    {ok, AppInfo} = request_api(get, api_path(["apps", erlang:binary_to_list(AppId)]), auth_header_()),
    ?assertEqual(<<"test 2">>, proplists:get_value(<<"name">>, get(data, AppInfo))),
    {ok, _} = request_api(delete, api_path(["apps", erlang:binary_to_list(AppId)]), auth_header_()),
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

    {ok, _} = request_api(delete, api_path(["banned", erlang:binary_to_list(Who)]), [], 
                          auth_header_(), [{<<"as">>, <<"client_id">>}]),
    {ok, Result2} = request_api(get, api_path(["banned"]), auth_header_()),
    ?assertEqual([], get(data, Result2)).

brokers(_) ->
    {ok, _} = request_api(get, api_path(["brokers"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["brokers", erlang:atom_to_list(node())]), auth_header_()).

configs(_) ->
    {ok, _} = request_api(get, api_path(["configs"]), auth_header_()),

    {ok, _} = request_api(get, api_path(["nodes",
                                         erlang:atom_to_list(node()),
                                         "configs"]), auth_header_()),

    {ok, _} = request_api(put, api_path(["nodes", 
                                         erlang:atom_to_list(node()),
                                         "plugin_configs",
                                         erlang:atom_to_list(emqx_reloader)]), [], 
                          auth_header_(), [{<<"reloader.interval">>, <<"60s">>},
                                           {<<"reloader.logfile">>, <<"reloader.log">>}]),

    {ok, Result} = request_api(get, api_path(["nodes",
                                              erlang:atom_to_list(node()),
                                              "plugin_configs",
                                              erlang:atom_to_list(emqx_reloader)]), auth_header_()),
    ?assert(lists:any(fun(Elem) -> 
                          case proplists:get_value(<<"key">>, Elem) of
                              <<"reloader.interval">> -> 
                                  <<"60s">> == proplists:get_value(<<"value">>, Elem);
                              _ -> false
                          end
                      end, get(data, Result))).

connections_and_sessions(_) ->
    with_connection(fun([Sock]) ->
                        ClientId = <<"myclient">>,
                        emqx_client_sock:send(Sock, raw_send_serialize(
                                                        ?CONNECT_PACKET(
                                                            #mqtt_packet_connect{
                                                                proto_ver   = ?MQTT_PROTO_V5,
                                                                clean_start = true,
                                                                client_id   = ClientId})
                                                    )),
                        {ok, Data} = gen_tcp:recv(Sock, 0),
                        {ok, ?CONNACK_PACKET(?RC_SUCCESS, 0), _} = raw_recv_parse(Data, ?MQTT_PROTO_V5),

                        {ok, Conns} = request_api(get, 
                                                  api_path(["connections"]), 
                                                  "_limit=100&_page=1", 
                                                  auth_header_()),
                        ?assertEqual(1, proplists:get_value(<<"count">>, get(meta, Conns))),
                        {ok, Conns} = request_api(get, 
                                                  api_path(["nodes", 
                                                            erlang:atom_to_list(node()), 
                                                            "connections"]), 
                                                  "_limit=100&_page=1", 
                                                  auth_header_()),

                        {ok, Result} = request_api(get, 
                                                   api_path(["nodes", 
                                                             erlang:atom_to_list(node()), 
                                                             "connections", 
                                                             erlang:binary_to_list(ClientId)]), 
                                                   auth_header_()),
                        [Conn] = get(data, Result),
                        ?assertEqual(ClientId, proplists:get_value(<<"client_id">>, Conn)),

                        {ok, Result} = request_api(get, 
                                                   api_path(["connections", 
                                                             erlang:binary_to_list(ClientId)]), 
                                                   auth_header_()),

                        {ok, Result2} = request_api(get, 
                                                    api_path(["sessions"]),
                                                    auth_header_()),
                        [Session] = get(data, Result2),
                        ?assertEqual(ClientId, proplists:get_value(<<"client_id">>, Session)),

                        {ok, Result2} = request_api(get, 
                                                    api_path(["nodes", 
                                                              erlang:atom_to_list(node()),
                                                              "sessions"]),
                                                    auth_header_()),
                        
                        {ok, Result3} = request_api(get, 
                                                    api_path(["sessions", 
                                                              erlang:binary_to_list(ClientId)]),
                                                    auth_header_()),
                        [Session] = get(data, Result3),

                        {ok, Result3} = request_api(get, 
                                                    api_path(["nodes", 
                                                              erlang:atom_to_list(node()),
                                                              "sessions",
                                                              erlang:binary_to_list(ClientId)]),
                                                    auth_header_()),

                        {ok, _} = request_api(delete, 
                                              api_path(["connections", 
                                                        erlang:binary_to_list(ClientId)]), 
                                              auth_header_()),

                        {ok, NonConn} = request_api(get, 
                                                    api_path(["connections"]), 
                                                    "_limit=100&_page=1", 
                                                    auth_header_()),

                        ?assertEqual([], get(data, NonConn)),

                        {ok, NonSession} = request_api(get, 
                                                       api_path(["sessions"]),
                                                       auth_header_()),
                        ?assertEqual([], get(data, NonSession))
                    end).

listeners(_) ->
    {ok, _} = request_api(get, api_path(["listeners"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", erlang:atom_to_list(node()), "listeners"]), auth_header_()).

metrics(_) ->
    {ok, _} = request_api(get, api_path(["metrics"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", erlang:atom_to_list(node()), "metrics"]), auth_header_()).

nodes(_) ->
    {ok, _} = request_api(get, api_path(["nodes"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", erlang:atom_to_list(node())]), auth_header_()).

plugins(_) ->
    {ok, _} = request_api(put, 
                          api_path(["nodes",
                                    erlang:atom_to_list(node()),
                                    "plugins",
                                    erlang:atom_to_list(emqx_reloader),
                                    "unload"]), 
                          auth_header_()),

    {ok, Result3} = request_api(get, 
                                api_path(["nodes",
                                          erlang:atom_to_list(node()),
                                          "plugins"]),
                                auth_header_()),
    [Plugin3] = filter(get(data, Result3), <<"emqx_reloader">>),
    ?assertEqual(<<"emqx_reloader">>, proplists:get_value(<<"name">>, Plugin3)),
    ?assertNot(proplists:get_value(<<"active">>, Plugin3)),

    {ok, _} = request_api(put, 
                          api_path(["nodes",
                                    erlang:atom_to_list(node()),
                                    "plugins",
                                    erlang:atom_to_list(emqx_reloader),
                                    "load"]), 
                          auth_header_()),
    
    {ok, Result} = request_api(get, api_path(["plugins"]), auth_header_()),
    [Plugins] = get(data, Result),
    [Plugin] = filter(proplists:get_value(<<"plugins">>, Plugins), <<"emqx_reloader">>),
    ?assertEqual(<<"emqx_reloader">>, proplists:get_value(<<"name">>, Plugin)),
    ?assert(proplists:get_value(<<"active">>, Plugin)),

    {ok, Result2} = request_api(get, 
                                api_path(["nodes",
                                          erlang:atom_to_list(node()),
                                          "plugins"]),
                                auth_header_()),
    [Plugin] = filter(get(data, Result2), <<"emqx_reloader">>).

    

pubsub(_) ->
    with_connection(fun([Sock]) ->
                        ClientId = <<"myclient">>,
                        Topic = <<"mytopic">>,
                        emqx_client_sock:send(Sock, raw_send_serialize(
                                                        ?CONNECT_PACKET(
                                                            #mqtt_packet_connect{
                                                                proto_ver   = ?MQTT_PROTO_V5,
                                                                clean_start = true,
                                                                client_id   = ClientId})
                                                    )),
                        {ok, Data} = gen_tcp:recv(Sock, 0),
                        {ok, ?CONNACK_PACKET(?RC_SUCCESS, 0), _} = raw_recv_parse(Data, ?MQTT_PROTO_V5),

                        emqx_client_sock:send(Sock, raw_send_serialize(?SUBSCRIBE_PACKET(1, [{Topic, #{rh  => 1,
                                                                                                       qos => ?QOS_2,
                                                                                                       rap => 0,
                                                                                                       nl  => 0,
                                                                                                       rc  => 0}}]),
                                                                        #{version => ?MQTT_PROTO_V5})),

                        {ok, SubData} = gen_tcp:recv(Sock, 0),
                        {ok, ?SUBACK_PACKET(1, #{}, [2]), _} = raw_recv_parse(SubData, ?MQTT_PROTO_V5),

                        {ok, Code} = request_api(post, 
                                                 api_path(["mqtt/subscribe"]), 
                                                 [], 
                                                 auth_header_(),
                                                 [{<<"client_id">>, ClientId},
                                                  {<<"topic">>, Topic},
                                                  {<<"qos">>, 2}]),
                        ?assertEqual(0, proplists:get_value(<<"code">>, jsx:decode(list_to_binary(Code)))),

                        {ok, Code} = request_api(post, 
                                                 api_path(["mqtt/publish"]), 
                                                 [], 
                                                 auth_header_(),
                                                 [{<<"client_id">>, ClientId},
                                                  {<<"topic">>, <<"mytopic">>},
                                                  {<<"qos">>, 1},
                                                  {<<"payload">>, <<"hello">>}]),

                        {ok, PubData} = gen_tcp:recv(Sock, 0),
                        {ok, ?PUBLISH_PACKET(?QOS_1, Topic, _, <<"hello">>), _} = raw_recv_parse(PubData, ?MQTT_PROTO_V5),

                        {ok, Code} = request_api(post, 
                                                 api_path(["mqtt/unsubscribe"]), 
                                                 [], 
                                                 auth_header_(),
                                                 [{<<"client_id">>, ClientId},
                                                  {<<"topic">>, Topic}])
                    end).

routes_and_subscriptions(_) ->
    with_connection(fun([Sock]) ->
                        {ok, NonRoute} = request_api(get, api_path(["routes"]), auth_header_()),
                        ?assertEqual([], get(data, NonRoute)),

                        ClientId = <<"myclient">>,
                        Topic = <<"mytopic">>,
                        emqx_client_sock:send(Sock, raw_send_serialize(
                                                        ?CONNECT_PACKET(
                                                            #mqtt_packet_connect{
                                                                proto_ver   = ?MQTT_PROTO_V5,
                                                                clean_start = true,
                                                                client_id   = ClientId})
                                                    )),
                        {ok, Data} = gen_tcp:recv(Sock, 0),
                        {ok, ?CONNACK_PACKET(?RC_SUCCESS, 0), _} = raw_recv_parse(Data, ?MQTT_PROTO_V5),

                        emqx_client_sock:send(Sock, raw_send_serialize(?SUBSCRIBE_PACKET(1, [{Topic, #{rh  => 1,
                                                                                                       qos => ?QOS_2,
                                                                                                       rap => 0,
                                                                                                       nl  => 0,
                                                                                                       rc  => 0}}]),
                                                                        #{version => ?MQTT_PROTO_V5})),

                        {ok, SubData} = gen_tcp:recv(Sock, 0),
                        {ok, ?SUBACK_PACKET(1, #{}, [2]), _} = raw_recv_parse(SubData, ?MQTT_PROTO_V5),

                        {ok, Result} = request_api(get, api_path(["routes"]), auth_header_()),
                        [Route] = get(data, Result),
                        ?assertEqual(Topic, proplists:get_value(<<"topic">>, Route)),
                        
                        {ok, Result2} = request_api(get, api_path(["routes", erlang:binary_to_list(Topic)]), auth_header_()),
                        [Route] = get(data, Result2),

                        {ok, Result3} = request_api(get, api_path(["subscriptions"]), auth_header_()),
                        [Subscription] = get(data, Result3),
                        ?assertEqual(Topic, proplists:get_value(<<"topic">>, Subscription)),
                        ?assertEqual(ClientId, proplists:get_value(<<"client_id">>, Subscription)),

                        {ok, Result3} = request_api(get, api_path(["nodes",
                                                                   erlang:atom_to_list(node()),
                                                                   "subscriptions"]), auth_header_()),

                        {ok, Result4} = request_api(get, api_path(["subscriptions",
                                                                         erlang:binary_to_list(ClientId)]), auth_header_()),
                        [Subscription] = get(data, Result4),

                        {ok, Result4} = request_api(get, api_path(["nodes",
                                                                   erlang:atom_to_list(node()),
                                                                   "subscriptions",
                                                                   erlang:binary_to_list(ClientId)]), auth_header_())
                    end).

stats(_) ->
    {ok, _} = request_api(get, api_path(["stats"]), auth_header_()),
    {ok, _} = request_api(get, api_path(["nodes", erlang:atom_to_list(node()), "stats"]), auth_header_()).

request_api(Method, Url, Auth) ->
    request_api(Method, Url, [], Auth, []).

request_api(Method, Url, QueryParams, Auth) ->
    request_api(Method, Url, QueryParams, Auth, []).

request_api(Method, Url, QueryParams, Auth, Body) ->
    NewUrl = case QueryParams of
                 [] ->
                     Url;
                 _ ->
                     Url ++ "?" ++ QueryParams
             end,
    Request = case Body of
                  [] ->
                      {NewUrl, [Auth]};
                  _ ->
                      {NewUrl, [Auth], "application/json", emqx_json:encode(Body)}
              end,
    do_request_api(Method, Request).

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
    auth_header_(erlang:binary_to_list(AppId), erlang:binary_to_list(AppSecret)).

auth_header_(User, Pass) ->
    Encoded = base64:encode_to_string(lists:append([User,":",Pass])),
    {"Authorization","Basic " ++ Encoded}.

api_path(Parts)->
    ?HOST ++ filename:join([?BASE_PATH, ?API_VERSION] ++ Parts).

raw_send_serialize(Packet) ->
    emqx_frame:serialize(Packet).

raw_send_serialize(Packet, Opts) ->
    emqx_frame:serialize(Packet, Opts).

raw_recv_parse(P, ProtoVersion) ->
    emqx_frame:parse(P, {none, #{max_packet_size => ?MAX_PACKET_SIZE,
                                 version         => ProtoVersion}}).

filter(List, Name) ->
    lists:filter(fun(Item) ->
        proplists:get_value(<<"name">>, Item) == Name
    end, List).
