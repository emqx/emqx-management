%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 EMQ Enterprise, Inc. (http://emqtt.io).
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

-module(emqx_mgmt).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("stdlib/include/qlc.hrl").

-include_lib("emqx/include/emqx.hrl").

-include_lib("emqx/include/emqx_mqtt.hrl").

-import(proplists, [get_value/2, get_value/3]).

%% Nodes and Brokers API
-export([list_nodes/0, lookup_node/1, list_brokers/0, lookup_broker/1,
         node_info/1, broker_info/1]).

%% Metrics and Stats
-export([get_metrics/0, get_metrics/1, get_stats/0, get_stats/1]).

%% Clients, Sessions
-export([list_clients/1, lookup_client/1, lookup_client/2,
         kickout_client/1, clean_acl_cache/2]).

-export([list_sessions/1, lookup_session/1, lookup_session/2]).

%% Subscriptions
-export([list_subscriptions/1, lookup_subscriptions/1, lookup_subscriptions/2]).

%% Routes
-export([list_routes/0, lookup_routes/1]).

%% PubSub
-export([subscribe/3, publish/1, unsubscribe/2]).

%% Plugins
-export([list_plugins/0, list_plugins/1, load_plugin/2, unload_plugin/2]).

%% Listeners
-export([list_listeners/0, list_listeners/1]).

%% Alarms
-export([get_alarms/0, get_alarms/1]).

%% Configs
-export([update_configs/2, update_config/3, update_config/4,
         get_all_configs/0, get_all_configs/1,
         get_plugin_configs/1, get_plugin_configs/2,
         update_plugin_configs/2, update_plugin_configs/3]).

%% Common Table API
-export([count/1, tables/1, query_handle/1, item/2, max_row_limit/0]).

-define(MAX_ROW_LIMIT, 10000).

-define(APP, emqx_management).

%%--------------------------------------------------------------------
%% Node Info
%%--------------------------------------------------------------------

list_nodes() ->
    Running = mnesia:system_info(running_db_nodes),
    Stopped = mnesia:system_info(db_nodes) -- Running,
    DownNodes = lists:map(fun stopped_node_info/1, Stopped),
    [{Node, node_info(Node)} || Node <- Running] ++ DownNodes.

lookup_node(Node) -> node_info(Node).

node_info(Node) when Node =:= node() ->
    Memory  = emqx_vm:get_memory(),
    Info = maps:from_list([{K, list_to_binary(V)} || {K, V} <- emqx_vm:loads()]),
    Info#{name              => node(),
          otp_release       => iolist_to_binary(otp_rel()),
          memory_total      => get_value(allocated, Memory),
          memory_used       => get_value(used, Memory),
          process_available => erlang:system_info(process_limit),
          process_used      => erlang:system_info(process_count),
          max_fds           => get_value(max_fds, erlang:system_info(check_io)),
          clients           => ets:info(mqtt_client, size),
          node_status       => 'Running'};
node_info(Node) ->
    rpc_call(Node, node_info, [Node]).

stopped_node_info(Node) ->
    #{name => Node, node_status => 'Stopped'}.

%%--------------------------------------------------------------------
%% Brokers
%%--------------------------------------------------------------------

list_brokers() ->
    [{Node, broker_info(Node)} || Node <- ekka_mnesia:running_nodes()].

lookup_broker(Node) ->
    broker_info(Node).

broker_info(Node) when Node =:= node() ->
    Info = maps:from_list([{K, iolist_to_binary(V)} || {K, V} <- emqx_broker:info()]),
    Info#{name => Node, otp_release => iolist_to_binary(otp_rel()), node_status => 'Running'};

broker_info(Node) ->
    rpc_call(Node, broker_info, [Node]).

%%--------------------------------------------------------------------
%% Metrics and Stats
%%--------------------------------------------------------------------

get_metrics() ->
    [{Node, get_metrics(Node)} || Node <- ekka_mnesia:running_nodes()].

get_metrics(Node) when Node =:= node() ->
    emqx_metrics:all();
get_metrics(Node) ->
    rpc_call(Node, get_metrics, [Node]).

get_stats() ->
    [{Node, get_stats(Node)} || Node <- ekka_mnesia:running_nodes()].

get_stats(Node) when Node =:= node() ->
    emqx_stats:getstats();
get_stats(Node) ->
    rpc_call(Node, get_stats, [Node]).

%%--------------------------------------------------------------------
%% Clients
%%--------------------------------------------------------------------

list_clients(Node) when Node =:= node() ->
    case check_row_limit([mqtt_client]) of
        ok -> ets:tab2list(mqtt_client);
        false -> throw(max_row_limit)
    end;

list_clients(Node) ->
    case rpc_call(Node, list_clients, [Node]) of
        max_row_limit -> throw(max_row_limit);
        Res -> Res
    end.

lookup_client(ClientId) ->
    lists:append([lookup_client(Node, ClientId) || Node <- ekka_mnesia:running_nodes()]).

lookup_client(Node, ClientId) when Node =:= node() ->
    ets:lookup(mqtt_client, ClientId);

lookup_client(Node, ClientId) ->
    rpc_call(Node, lookup_client, [Node, ClientId]).

kickout_client(ClientId) ->
    Results = [kickout_client(Node, ClientId) || Node <- ekka_mnesia:running_nodes()],
    case lists:any(fun(Item) -> Item =:= ok end, Results) of
        true  -> ok;
        false -> lists:last(Results)
    end.

kickout_client(Node, ClientId) when Node =:= node() ->
    case emqx_cm:lookup(ClientId) of
        undefined -> {error, not_found};
        #mqtt_client{client_pid = Pid} -> emqx_client:kick(Pid)
    end;

kickout_client(Node, ClientId) ->
    rpc_call(Node, kickout_client, [Node, ClientId]).

clean_acl_cache(ClientId, Topic) ->
    Results = [clean_acl_cache(Node, ClientId, Topic) || Node <- ekka_mnesia:running_nodes()],
    case lists:any(fun(Item) -> Item =:= ok end, Results) of
        true  -> ok;
        false -> lists:last(Results)
    end.

clean_acl_cache(Node, ClientId, Topic) when Node =:= node() ->
    case emqx_cm:lookup(ClientId) of
        undefined -> {error, not_found};
        #mqtt_client{client_pid = Pid}-> emqx_client:clean_acl_cache(Pid, Topic)
    end;
clean_acl_cache(Node, ClientId, Topic) ->
    rpc_call(Node, clean_acl_cache, [Node, ClientId, Topic]).

%%--------------------------------------------------------------------
%% Sessions
%%--------------------------------------------------------------------

list_sessions(Node) when Node =:= node() ->
    case check_row_limit([mqtt_local_session]) of
        false -> throw(max_row_limit);
        ok    -> [item(session, Item) || Item <- ets:tab2list(mqtt_local_session)]
    end;

list_sessions(Node) ->
    case rpc_call(Node, list_sessions, [Node]) of
        max_row_limit -> throw(max_row_limit);
        Res -> Res
    end.

lookup_session(ClientId) ->
    lists:append([lookup_session(Node, ClientId) || Node <- ekka_mnesia:running_nodes()]).

lookup_session(Node, ClientId) when Node =:= node() ->
    [item(session, Item) || Item <- ets:lookup(mqtt_local_session, ClientId)];

lookup_session(Node, ClientId) ->
    rpc_call(Node, lookup_session, [Node, ClientId]).

%%--------------------------------------------------------------------
%% Subscriptions
%%--------------------------------------------------------------------

list_subscriptions(Node) when Node =:= node() ->
    case check_row_limit([mqtt_subproperty]) of
        false -> throw(max_row_limit);
        ok    -> [item(subscription, Sub) || Sub <- ets:tab2list(mqtt_subproperty)]
    end;

list_subscriptions(Node) ->
    rpc_call(Node, list_subscriptions, [Node]).

lookup_subscriptions(Key) ->
    lists:append([lookup_subscriptions(Node, Key) || Node <- ekka_mnesia:running_nodes()]).
 
lookup_subscriptions(Node, Key) when Node =:= node() ->
    Keys = ets:lookup(mqtt_subscription, Key),
    Subscriptions =
    case length(Keys) == 0 of
        true ->
            ets:match_object(mqtt_subproperty, {{Key, '_'}, '_'});
        false ->
            lists:append([ets:lookup(mqtt_subproperty, {T, S}) || {T, S} <- Keys])
    end,
    [item(subscription, Sub) || Sub <- Subscriptions];

lookup_subscriptions(Node, Key) ->
    rpc_call(Node, lookup_subscriptions, [Node, Key]).

%%--------------------------------------------------------------------
%% Routes
%%--------------------------------------------------------------------

list_routes() ->
    case check_row_limit(tables(routes)) of
        false -> throw(max_row_limit);
        ok ->
            [item(route, R) || R <- lists:append([ets:tab2list(Tab) || Tab <- tables(routes)])]
    end.

lookup_routes(Topic) ->
    [item(route, R) || R <- lists:append([ets:lookup(Tab, Topic) || Tab <- tables(routes)])].

%%--------------------------------------------------------------------
%% PubSub
%%--------------------------------------------------------------------

subscribe(ClientId, Topic, Qos) ->
    case emqx_sm:lookup_session(ClientId) of
        undefined -> {error, session_not_found};
        #mqtt_session{sess_pid = SessPid} ->
            emqx_session:subscribe(SessPid, [{Topic, [{qos, Qos}]}])
    end.

%%TODO: ???
publish(Msg) -> emqx:publish(Msg).

unsubscribe(ClientId, Topic) ->
    case emqx_sm:lookup_session(ClientId) of
        undefined -> {error, session_not_found};
        #mqtt_session{sess_pid = SessPid} ->
            emqx_session:unsubscribe(SessPid, [{Topic, []}])
    end.

%%--------------------------------------------------------------------
%% Plugins
%%--------------------------------------------------------------------

list_plugins() ->
    [{Node, list_plugins(Node)} || Node <- ekka_mnesia:running_nodes()].

list_plugins(Node) when Node =:= node() ->
    emqx_plugins:list(Node);
list_plugins(Node) ->
    rpc_call(Node, list_plugins, [Node]).

load_plugin(Node, Plugin) when Node =:= node() ->
    emqx_plugins:load(Plugin);
load_plugin(Node, Plugin) ->
    rpc_call(Node, load_plugin, [Node, Plugin]).

unload_plugin(Node, Plugin) when Node =:= node() ->
    emqx_plugins:unload(Plugin);
unload_plugin(Node, Plugin) ->
    rpc_call(Node, unload_plugin, [Node, Plugin]).

%%--------------------------------------------------------------------
%% Listeners
%%--------------------------------------------------------------------

list_listeners() ->
    [{Node, list_listeners(Node)} || Node <- ekka_mnesia:running_nodes()].

list_listeners(Node) when Node =:= node() ->
    lists:map(fun({{Protocol, ListenOn}, Pid}) ->
                #{protocol        => Protocol,
                  listen_on       => ListenOn,
                  acceptors       => esockd:get_acceptors(Pid),
                  max_clients     => esockd:get_max_clients(Pid),
                  current_clients => esockd:get_current_clients(Pid),
                  shutdown_count  => esockd:get_shutdown_count(Pid)}
              end, esockd:listeners());

list_listeners(Node) ->
    rpc_call(Node, list_listeners, [Node]).

%%--------------------------------------------------------------------
%% Get Alarms
%%--------------------------------------------------------------------

get_alarms() ->
    [{Node, get_alarms(Node)} || Node <- ekka_mnesia:running_nodes()].
   
get_alarms(Node) when Node =:= node() ->
    emqx_alarm:get_alarms();
get_alarms(Node) ->
    rpc_call(Node, get_alarms, [Node]).

%%--------------------------------------------------------------------
%% Config ENV
%%--------------------------------------------------------------------

update_configs(App, Terms) ->
    emqx_config:write(App, Terms).

update_config(App, Key, Value) ->
    Results = [update_config(Node, App, Key, Value) || Node <- ekka_mnesia:running_nodes()],
    case lists:any(fun(Item) -> Item =:= ok end, Results) of
        true  -> ok;
        false -> lists:last(Results)
    end.

update_config(Node, App, Key, Value) when Node =:= node() ->
    emqx_config:set(App, Key, Value);

update_config(Node, App, Key, Value) ->
    rpc_call(Node, update_config, [Node, App, Key, Value]).

get_all_configs() ->
    [{Node, get_all_configs(Node)} || Node <- ekka_mnesia:running_nodes()].

get_all_configs(Node) when Node =:= node()->
    emqx_cli_config:all_cfgs();

get_all_configs(Node) ->
    rpc_call(Node, get_config, [Node]).

get_plugin_configs(PluginName) ->
    emqx_config:read(PluginName).

get_plugin_configs(Node, PluginName) ->
    rpc_call(Node, get_plugin_configs, [PluginName]).

update_plugin_configs(PluginName, Terms) ->
    emqx_config:write(PluginName, Terms).

update_plugin_configs(Node, PluginName, Terms) ->
    rpc_call(Node, update_plugin_configs, [PluginName, Terms]).

%%--------------------------------------------------------------------
%% Common Table API
%%--------------------------------------------------------------------

count(clients) ->
    table_size(mqtt_client);

count(sessions) ->
    table_size(mqtt_local_session);

count(subscriptions) ->
    table_size(mqtt_subproperty);

count(routes) ->
    lists:sum([table_size(Tab) || Tab <- tables(routes)]).

query_handle(clients) ->
    qlc:q([Client || Client <- ets:table(mqtt_client)]);

query_handle(sessions) ->
    qlc:q([Session || Session <- ets:table(mqtt_local_session)]);

query_handle(subscriptions) ->
    qlc:q([E || E <- ets:table(mqtt_subproperty)]);

query_handle(routes) ->
    qlc:append([qlc:q([E || E <- ets:table(Tab)]) || Tab <- tables(routes)]).

tables(clients) -> [mqtt_client];

tables(sessions) -> [mqtt_local_session];

tables(routes) -> [mqtt_route, mqtt_local_route].

item(session, {ClientId, _Pid, Persistent, Properties}) ->
    maps:from_list(
      [{client_id, ClientId}, {clean_sess, not Persistent},
       {created_at, get_value(created_at, Properties)}
       | emqx_stats:get_session_stats(ClientId)]);

item(subscription, {{Topic, ClientId}, Options}) ->
    #{topic => Topic, clientid => ClientId, options => Options};

item(route, #mqtt_route{topic = Topic, node = Node}) ->
    #{topic => Topic, node => Node};
item(route, {Topic, Node}) ->
    #{topic => Topic, node => Node}.

%%--------------------------------------------------------------------
%% Internel Functions.
%%--------------------------------------------------------------------

rpc_call(Node, Fun, Args) ->
    case rpc:call(Node, ?MODULE, Fun, Args) of
        {badrpc, Reason} -> {error, Reason};
        Res -> Res
    end.

otp_rel() ->
    lists:concat(["R", erlang:system_info(otp_release), "/", erlang:system_info(version)]).

check_row_limit(Tables) ->
    check_row_limit(Tables, max_row_limit()).

check_row_limit([], _Limit) ->
    ok;
check_row_limit([Tab|Tables], Limit) ->
    case table_size(Tab) > Limit of
        true  -> false;
        false -> check_row_limit(Tables, Limit)
    end.

max_row_limit() ->
    application:get_env(?APP, max_row_limit, ?MAX_ROW_LIMIT).

table_size(Tab) -> ets:info(Tab, size).

