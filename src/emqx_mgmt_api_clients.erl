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

-module(emqx_mgmt_api_clients).

-include_lib("emqx/include/emqx_mqtt.hrl").
-include_lib("emqx/include/emqx.hrl").

-rest_api(#{name   => list_clients,
            method => 'GET',
            path   => "/clients/",
            func   => list,
            descr  => "A list of clients in the cluster"}).

-rest_api(#{name   => list_node_clients,
            method => 'GET',
            path   => "nodes/:atom:node/clients/",
            func   => list,
            descr  => "A list of clients on a node"}).

-rest_api(#{name   => lookup_node_client,
            method => 'GET',
            path   => "nodes/:atom:node/clients/:bin:clientid",
            func   => lookup,
            descr  => "Lookup a client on node"}).

-rest_api(#{name   => lookup_client,
            method => 'GET',
            path   => "/clients/:bin:clientid",
            func   => lookup,
            descr  => "Lookup a client in the cluster"}).

-rest_api(#{name   => kickout_client,
            method => 'DELETE',
            path   => "/clients/:bin:clientid",
            func   => kickout,
            descr  => "Kick out a client"}).

-rest_api(#{name   => clean_acl_cache,
            method => 'DELETE',
            path   => "/clients/:bin:clientid/acl/:bin:topic",
            func   => clean_acl_cache,
            descr  => "Clean ACL cache of a client"}).

-import(emqx_mgmt_util, [ntoa/1, strftime/1]).

-export([list/2, lookup/2, kickout/2, clean_acl_cache/2]).

list(Bindings, Params) when map_size(Bindings) == 0 ->
    %%TODO: across nodes?
    list(#{node => node()}, Params);

list(#{node := Node}, Params) when Node =:= node() ->
    {ok, emqx_mgmt_api:paginate(emqx_client, Params, fun format/1)};

list(Bindings = #{node := Node}, Params) ->
    case rpc:call(Node, ?MODULE, list, [Bindings, Params]) of
        {badrpc, Reason} -> {error, #{message => Reason}};
        Res -> Res
    end.

lookup(#{node := Node, clientid := ClientId}, _Params) ->
    {ok, format(emqx_mgmt:lookup_client(Node, ClientId))};

lookup(#{clientid := ClientId}, _Params) ->
    {ok, format(emqx_mgmt:lookup_client(ClientId))}.

kickout(#{clientid := ClientId}, _Params) ->
    case emqx_mgmt:kickout_client(ClientId) of
        ok -> ok;
        {error, Reason} -> {error, #{message => Reason}}
    end.

clean_acl_cache(#{clientid := ClientId, topic := Topic}, _Params) ->
    emqx_mgmt:clean_acl_cache(ClientId, Topic).

format({ClientId, Pid}) ->
    case ets:lookup(emqx_client_attrs, {ClientId, Pid}) of
        [{_, Val}] -> format(maps:from_list(Val));
        _ -> []
    end;

format(Clients) when is_list(Clients) ->
    lists:map(fun({ClientId, Pid}) ->
        case ets:lookup(emqx_client_attrs, {ClientId, Pid}) of
            [{_, Val}] -> format(maps:from_list(Val));
            _ -> []
        end
    end, Clients);

format(#{}) ->
    #{};
format(#{client_id    := ClientId,
         peername     := {IpAddr, Port},
         username     := Username,
         clean_start  := CleanSess,
         proto_ver    := ProtoVer,
         keepalive    := KeepAlvie,
         connected_at := ConnectedAt}) ->
    #{node         => node(),
      client_id    => ClientId,
      username     => Username,
      ipaddress    => iolist_to_binary(ntoa(IpAddr)),
      port         => Port,
      clean_sess   => CleanSess,
      proto_ver    => ProtoVer,
      keepalive    => KeepAlvie,
      connected_at => iolist_to_binary(strftime(ConnectedAt))}.

