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

-module(emqx_mgmt_api_connections).

-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("emqx/include/emqx.hrl").

-rest_api(#{name   => list_connections,
            method => 'GET',
            path   => "/connections/",
            func   => list,
            descr  => "A list of connections in the cluster"}).

-rest_api(#{name   => list_node_connections,
            method => 'GET',
            path   => "nodes/:atom:node/connections/",
            func   => list,
            descr  => "A list of connections on a node"}).

-rest_api(#{name   => lookup_node_connections,
            method => 'GET',
            path   => "nodes/:atom:node/connections/:bin:clientid",
            func   => lookup,
            descr  => "Lookup a connection on node"}).

-rest_api(#{name   => lookup_connections,
            method => 'GET',
            path   => "/connections/:bin:clientid",
            func   => lookup,
            descr  => "Lookup a connection in the cluster"}).

-rest_api(#{name   => kickout_connection,
            method => 'DELETE',
            path   => "/connections/:bin:clientid",
            func   => kickout,
            descr  => "Kick out a connection"}).

-import(emqx_mgmt_util, [ntoa/1, strftime/1]).

-export([list/2, lookup/2, kickout/2]).

list(Bindings, Params) when map_size(Bindings) == 0 ->
    %%TODO: across nodes?
    list(#{node => node()}, Params);

list(#{node := Node}, Params) when Node =:= node() ->
    {ok, emqx_mgmt_api:paginate(emqx_conn, Params, fun format/1)};

list(Bindings = #{node := Node}, Params) ->
    case rpc:call(Node, ?MODULE, list, [Bindings, Params]) of
        {badrpc, Reason} -> {error, #{message => Reason}};
        Res -> Res
    end.

lookup(#{node := Node, clientid := ClientId}, _Params) ->
    {ok, emqx_mgmt:lookup_conn(Node, http_uri:decode(ClientId), fun format/1)};

lookup(#{clientid := ClientId}, _Params) ->
    {ok, emqx_mgmt:lookup_conn(http_uri:decode(ClientId), fun format/1)}.

kickout(#{clientid := ClientId}, _Params) ->
    case emqx_mgmt:kickout_conn(http_uri:decode(ClientId)) of
        ok -> ok;
        {error, Reason} -> {error, #{message => Reason}}
    end.

format(ClientList) when is_list(ClientList) ->
    [format(Client) || Client <- ClientList];
format(Client = {_ClientId, _Pid}) ->
    Data = get_emqx_conn_attrs(Client) ++ get_emqx_conn_stats(Client),
    adjust_format(maps:from_list(Data)).

get_emqx_conn_attrs(TabKey) ->
    case ets:lookup(emqx_conn_attrs, TabKey) of
        [{_, Val}] -> Val;
        _ -> []
    end.

get_emqx_conn_stats(TabKey) ->
    case ets:lookup(emqx_conn_stats, TabKey) of
        [{_, Val1}] -> Val1;
        _ -> []
    end.

adjust_format(Data) when is_map(Data)->
    {IpAddr, Port} = maps:get(peername, Data),
    ConnectedAt = maps:get(connected_at, Data),
    maps:remove(peername, Data#{node         => node(),
                                ipaddress    => iolist_to_binary(ntoa(IpAddr)),
                                port         => Port,
                                connected_at => iolist_to_binary(strftime(ConnectedAt))}).
