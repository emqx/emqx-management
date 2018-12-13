-module(emqx_mgmt_api_SUITE).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").

-define(CONTENT_TYPE, "application/x-www-form-urlencoded").

-define(HOST, "http://127.0.0.1:18083/").

-define(API_VERSION, "v3").

-define(BASE_PATH, "api").

all() -> 
    [{group, rest_api}].

groups() ->
    [{rest_api, [sequence], [alarms, 
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
    application:load(emqx_retainer),
    [start_apps(App, {SchemaFile, ConfigFile}) ||
        {App, SchemaFile, ConfigFile}
            <- [{emqx, local_path("deps/emqx/priv/emqx.schema"),
                       local_path("deps/emqx/etc/emqx.conf")},
                {emqx_management, local_path("priv/emqx_management.schema"),
                                  local_path("etc/emqx_management.conf")},
                {emqx_dashboard, local_path("deps/emqx_dashboard/priv/emqx_dashboard.schema"),
                                 local_path("deps/emqx_dashboard/etc/emqx_dashboard.conf")},
                {emqx_retainer, local_path("deps/emqx_retainer/priv/emqx_retainer.schema"),
                                  local_path("deps/emqx_retainer/etc/emqx_retainer.conf")}]],
    ekka_mnesia:start(),
    emqx_mgmt_auth:mnesia(boot),
    Config.

end_per_suite(_Config) ->
    [application:stop(App) || App <- [emqx_retainer, emqx_dashboard, emqx_management, emqx]],
    ekka_mnesia:ensure_stopped().

get_base_dir() ->
    {file, Here} = code:is_loaded(?MODULE),
    filename:dirname(filename:dirname(Here)).

local_path(RelativePath) ->
    filename:join([get_base_dir(), RelativePath]).

start_apps(App, {SchemaFile, ConfigFile}) ->
    read_schema_configs(App, {SchemaFile, ConfigFile}),
    set_special_configs(App),
    application:ensure_all_started(App).

read_schema_configs(App, {SchemaFile, ConfigFile}) ->
    ct:pal("Read configs - SchemaFile: ~p, ConfigFile: ~p", [SchemaFile, ConfigFile]),
    Schema = cuttlefish_schema:files([SchemaFile]),
    Conf = conf_parse:file(ConfigFile),
    NewConfig = cuttlefish_generator:map(Schema, Conf),
    Vals = proplists:get_value(App, NewConfig, []),
    [application:set_env(App, Par, Value) || {Par, Value} <- Vals].

set_special_configs(emqx) ->
    application:set_env(emqx, plugins_loaded_file,
                        local_path("deps/emqx/test/emqx_SUITE_data/loaded_plugins")),
    PluginsEtcDir = local_path("deps/emqx_retainer/etc/") ++ "/",
    application:set_env(emqx, plugins_etc_dir, PluginsEtcDir);
set_special_configs(_App) ->
    ok.

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

alarms(_) ->
    AlarmTest = #alarm{id = <<"1">>, severity = error, title="alarm title", summary="alarm summary"},
    emqx_alarm_mgr:set_alarm(AlarmTest),
    [Alarm] = emqx_alarm_mgr:get_alarms(),
    ?assertEqual(error, Alarm#alarm.severity),
    {ok, _} = request_dashbaord(get, api_path(["alarms"]), auth_header_()),
    {ok, _} = request_dashbaord(get, api_path(["alarms", erlang:atom_to_list(node())]), auth_header_()).

apps(_) ->
    AppId = <<"123456">>,
    {ok, _} = request_dashbaord(post, api_path(["apps"]), [], 
                                auth_header_(), [{<<"app_id">>, AppId},
                                                 {<<"name">>,   <<"test">>},
                                                 {<<"status">>, true}]),

    {ok, _} = request_dashbaord(get, api_path(["apps"]), auth_header_()),
    {ok, _} = request_dashbaord(get, api_path(["apps", erlang:binary_to_list(AppId)]), auth_header_()),
    {ok, _} = request_dashbaord(put, api_path(["apps", erlang:binary_to_list(AppId)]), [],
                                auth_header_(), [{<<"name">>, <<"test 2">>},
                                                 {<<"status">>, true}]),
    {ok, AppInfo} = request_dashbaord(get, api_path(["apps", erlang:binary_to_list(AppId)]), auth_header_()),
    ?assertEqual(<<"test 2">>, proplists:get_value(<<"name">>, jsx:decode(list_to_binary(AppInfo)))),
    {ok, _} = request_dashbaord(delete, api_path(["apps", erlang:binary_to_list(AppId)]), auth_header_()),
    {ok, "[]"} = request_dashbaord(get, api_path(["apps"]), auth_header_()).

banned(_) ->
    Who = <<"myclient">>,    
    {ok, _} = request_dashbaord(post, api_path(["banned"]), [], 
                                auth_header_(), [{<<"who">>, Who},
                                                 {<<"as">>, <<"client_id">>},
                                                 {<<"reason">>, <<"test">>},
                                                 {<<"by">>, <<"dashboard">>},
                                                 {<<"desc">>, <<"hello world">>},
                                                 {<<"until">>, erlang:system_time(second) + 10}]),

    {ok, Result} = request_dashbaord(get, api_path(["banned"]), auth_header_()),
    [Banned] = proplists:get_value(<<"items">>, jsx:decode(list_to_binary(Result))),
    ?assertEqual(Who, proplists:get_value(<<"who">>, Banned)),

    {ok, _} = request_dashbaord(delete, api_path(["banned", erlang:binary_to_list(Who)]), [], 
                                auth_header_(), [{<<"as">>, <<"client_id">>}]),

    {ok, Result2} = request_dashbaord(get, api_path(["banned"]), auth_header_()),
    ?assertEqual([], proplists:get_value(<<"items">>, jsx:decode(list_to_binary(Result2)))).

brokers(_) ->
    {ok, _} = request_dashbaord(get, api_path(["brokers"]), auth_header_()),
    {ok, _} = request_dashbaord(get, api_path(["brokers", erlang:atom_to_list(node())]), auth_header_()).

configs(_) ->
    {ok, _} = request_dashbaord(get, api_path(["configs"]), auth_header_()),

    {ok, _} = request_dashbaord(get, api_path(["nodes",
                                               erlang:atom_to_list(node()),
                                               "configs"]), auth_header_()),

    {ok, _} = request_dashbaord(put, api_path(["nodes", 
                                               erlang:atom_to_list(node()),
                                               "plugin_configs",
                                               erlang:atom_to_list(emqx_retainer)]), [], 
                                auth_header_(), [{<<"retainer.expiry_interval">>, <<"100">>},
                                                 {<<"retainer.max_payload_size">>, <<"2MB">>},
                                                 {<<"retainer.max_retained_messages">>, <<"100">>},
                                                 {<<"retainer.storage_type">>, <<"ram">>}]),

    {ok, Result} = request_dashbaord(get, api_path(["nodes",
                                                    erlang:atom_to_list(node()),
                                                    "plugin_configs",
                                                    erlang:atom_to_list(emqx_retainer)]), auth_header_()),
    ?assert(lists:any(fun(Elem) -> 
                          case proplists:get_value(<<"key">>, Elem) of
                              <<"retainer.max_retained_messages">> -> 
                                  <<"100">> == proplists:get_value(<<"value">>, Elem);
                              _ -> false
                          end
                      end, jsx:decode(list_to_binary(Result)))).

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

                        {ok, Conns} = request_dashbaord(get, 
                                                        api_path(["connections"]), 
                                                        "_limit=100&_page=1", 
                                                        auth_header_()),

                        ?assertEqual(1, proplists:get_value(<<"count">>, 
                                                            proplists:get_value(<<"meta">>, 
                                                                                jsx:decode(list_to_binary(Conns))))),
                        {ok, Conns} = request_dashbaord(get, 
                                                        api_path(["nodes", 
                                                                  erlang:atom_to_list(node()), 
                                                                  "connections"]), 
                                                        "_limit=100&_page=1", 
                                                        auth_header_()),

                        {ok, Result} = request_dashbaord(get, 
                                                         api_path(["nodes", 
                                                                   erlang:atom_to_list(node()), 
                                                                   "connections", 
                                                                   erlang:binary_to_list(ClientId)]), 
                                                         auth_header_()),
                        [Conn] = jsx:decode(list_to_binary(Result)),
                        ?assertEqual(ClientId, proplists:get_value(<<"client_id">>, Conn)),

                        {ok, Result} = request_dashbaord(get, 
                                                         api_path(["connections", 
                                                                   erlang:binary_to_list(ClientId)]), 
                                                         auth_header_()),

                        {ok, Result2} = request_dashbaord(get, 
                                                          api_path(["sessions"]),
                                                          auth_header_()),
                        [Session] = proplists:get_value(<<"items">>, jsx:decode(list_to_binary(Result2))),
                        ?assertEqual(ClientId, proplists:get_value(<<"client_id">>, Session)),

                        {ok, Result2} = request_dashbaord(get, 
                                                          api_path(["nodes", 
                                                                    erlang:atom_to_list(node()),
                                                                    "sessions"]),
                                                          auth_header_()),
                        
                        {ok, Result3} = request_dashbaord(get, 
                                                          api_path(["sessions", 
                                                                    erlang:binary_to_list(ClientId)]),
                                                          auth_header_()),
                        [Session] = jsx:decode(list_to_binary(Result3)),

                        {ok, Result3} = request_dashbaord(get, 
                                                          api_path(["nodes", 
                                                                    erlang:atom_to_list(node()),
                                                                    "sessions",
                                                                    erlang:binary_to_list(ClientId)]),
                                                          auth_header_()),

                        {ok, _} = request_dashbaord(delete, 
                                                    api_path(["connections", 
                                                              erlang:binary_to_list(ClientId)]), 
                                                    auth_header_()),

                        {ok, NonConn} = request_dashbaord(get, 
                                                          api_path(["connections"]), 
                                                          "_limit=100&_page=1", 
                                                          auth_header_()),

                        ?assertEqual([], proplists:get_value(<<"items">>, jsx:decode(list_to_binary(NonConn)))),

                        {ok, NonSession} = request_dashbaord(get, 
                                                             api_path(["sessions"]),
                                                             auth_header_()),
                        ?assertEqual([], proplists:get_value(<<"items">>, jsx:decode(list_to_binary(NonSession))))
                    end).

listeners(_) ->
    {ok, _} = request_dashbaord(get, api_path(["listeners"]), auth_header_()),
    {ok, _} = request_dashbaord(get, api_path(["nodes", erlang:atom_to_list(node()), "listeners"]), auth_header_()).

metrics(_) ->
    {ok, _} = request_dashbaord(get, api_path(["metrics"]), auth_header_()),
    {ok, _} = request_dashbaord(get, api_path(["nodes", erlang:atom_to_list(node()), "metrics"]), auth_header_()).

nodes(_) ->
    {ok, _} = request_dashbaord(get, api_path(["nodes"]), auth_header_()),
    {ok, _} = request_dashbaord(get, api_path(["nodes", erlang:atom_to_list(node())]), auth_header_()).

plugins(_) ->
    {ok, _} = request_dashbaord(put, 
                                api_path(["nodes",
                                          erlang:atom_to_list(node()),
                                          "plugins",
                                          erlang:atom_to_list(emqx_retainer),
                                          "unload"]), 
                                auth_header_()),

    {ok, Result3} = request_dashbaord(get, 
                                      api_path(["nodes",
                                                erlang:atom_to_list(node()),
                                                "plugins"]),
                                      auth_header_()),
    [Plugin3] = jsx:decode(list_to_binary(Result3)),
    ?assertEqual(<<"emqx_retainer">>, proplists:get_value(<<"name">>, Plugin3)),
    ?assertNot(proplists:get_value(<<"active">>, Plugin3)),

    {ok, _} = request_dashbaord(put, 
                                api_path(["nodes",
                                          erlang:atom_to_list(node()),
                                          "plugins",
                                          erlang:atom_to_list(emqx_retainer),
                                          "load"]), 
                                auth_header_()),
    
    {ok, Result} = request_dashbaord(get, api_path(["plugins"]), auth_header_()),
    [Plugins] = jsx:decode(list_to_binary(Result)),
    [Plugin] = proplists:get_value(<<"plugins">>, Plugins),
    ?assertEqual(<<"emqx_retainer">>, proplists:get_value(<<"name">>, Plugin)),
    ?assert(proplists:get_value(<<"active">>, Plugin)),

    {ok, Result2} = request_dashbaord(get, 
                                      api_path(["nodes",
                                                erlang:atom_to_list(node()),
                                                "plugins"]),
                                      auth_header_()),
    [Plugin] = jsx:decode(list_to_binary(Result2)).

    

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

                        {ok, Code} = request_dashbaord(post, 
                                                       api_path(["mqtt/subscribe"]), 
                                                       [], 
                                                       auth_header_(),
                                                       [{<<"client_id">>, ClientId},
                                                        {<<"topic">>, Topic},
                                                        {<<"qos">>, 2}]),
                        ?assertEqual(0, proplists:get_value(<<"code">>, jsx:decode(list_to_binary(Code)))),

                        {ok, Code} = request_dashbaord(post, 
                                                       api_path(["mqtt/publish"]), 
                                                       [], 
                                                       auth_header_(),
                                                       [{<<"client_id">>, ClientId},
                                                        {<<"topic">>, <<"mytopic">>},
                                                        {<<"qos">>, 1},
                                                        {<<"payload">>, <<"hello">>}]),

                        {ok, PubData} = gen_tcp:recv(Sock, 0),
                        {ok, ?PUBLISH_PACKET(?QOS_1, Topic, _, <<"hello">>), _} = raw_recv_parse(PubData, ?MQTT_PROTO_V5),

                        {ok, Code} = request_dashbaord(post, 
                                                       api_path(["mqtt/unsubscribe"]), 
                                                       [], 
                                                       auth_header_(),
                                                       [{<<"client_id">>, ClientId},
                                                        {<<"topic">>, Topic}])
                    end).

routes_and_subscriptions(_) ->
    with_connection(fun([Sock]) ->
                        {ok, NonRoute} = request_dashbaord(get, api_path(["routes"]), auth_header_()),
                        ?assertEqual([], proplists:get_value(<<"items">>, jsx:decode(list_to_binary(NonRoute)))),

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

                        {ok, Result} = request_dashbaord(get, api_path(["routes"]), auth_header_()),
                        [Route] = proplists:get_value(<<"items">>, jsx:decode(list_to_binary(Result))),
                        ?assertEqual(Topic, proplists:get_value(<<"topic">>, Route)),
                        
                        {ok, Result2} = request_dashbaord(get, api_path(["routes", erlang:binary_to_list(Topic)]), auth_header_()),
                        [Route] = jsx:decode(list_to_binary(Result2)),

                        {ok, Result3} = request_dashbaord(get, api_path(["subscriptions"]), auth_header_()),
                        [Subscription] = proplists:get_value(<<"items">>, jsx:decode(list_to_binary(Result3))),
                        ?assertEqual(Topic, proplists:get_value(<<"topic">>, Subscription)),
                        ?assertEqual(ClientId, proplists:get_value(<<"client_id">>, Subscription)),

                        {ok, Result3} = request_dashbaord(get, api_path(["nodes",
                                                                         erlang:atom_to_list(node()),
                                                                         "subscriptions"]), auth_header_()),

                        {ok, Result4} = request_dashbaord(get, api_path(["subscriptions",
                                                                         erlang:binary_to_list(ClientId)]), auth_header_()),
                        [Subscription] = jsx:decode(list_to_binary(Result4)),

                        {ok, Result4} = request_dashbaord(get, api_path(["nodes",
                                                                         erlang:atom_to_list(node()),
                                                                         "subscriptions",
                                                                         erlang:binary_to_list(ClientId)]), auth_header_())
                    end).

stats(_) ->
    {ok, _} = request_dashbaord(get, api_path(["stats"]), auth_header_()),
    {ok, _} = request_dashbaord(get, api_path(["nodes", erlang:atom_to_list(node()), "stats"]), auth_header_()).

request_dashbaord(Method, Url, Auth) ->
    request_dashbaord(Method, Url, [], Auth, []).

request_dashbaord(Method, Url, QueryParams, Auth) ->
    request_dashbaord(Method, Url, QueryParams, Auth, []).

request_dashbaord(Method, Url, QueryParams, Auth, Body) ->
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
    do_request_dashbaord(Method, Request).

do_request_dashbaord(Method, Request)->
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
    auth_header_("admin", "public").

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