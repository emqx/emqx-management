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

-module(emq_mgmt_api_clients).

-include_lib("emqttd/include/emqttd.hrl").

-rest_api(#{name   => list_node_clients,
            method => 'GET',
            path   => "nodes/:node/clients/",
            func   => list,
            descr  => "A list of clients on a node"}).

-rest_api(#{name   => lookup_node_client,
            method => 'GET',
            path   => "nodes/:node/clients/:clientid",
            func   => lookup,
            descr  => "Lookup a client on node"}).

-rest_api(#{name   => lookup_client,
            method => 'GET',
            path   => "/clients/:clientid",
            func   => lookup,
            descr  => "Lookup a client in the cluster"}).

-rest_api(#{name   => kickout_client,
            method => 'DELETE',
            path   => "/clients/:clientid",
            func   => kickout,
            descr  => "Kick out a client"}).

-rest_api(#{name   => clean_acl_cache,
            method => 'PUT',
            path   => "/clients/:clientid/clean_acl_cache",
            func   => clean_acl_cache,
            descr  => "Clean acl cache of a client"}).

-import(emq_mgmt_util, [ntoa/1, strftime/1]).

list(#{node := Node}, Params) when Node =:= node() ->
    {ok, emq_mgmt_api:paginate(emq_mgmt:query_handle(clients),
                               emq_mgmt:count(clients),
                               Params, fun format/1)};

list(Bindings = #{node := Node}, Params) ->
    case rpc:call(Node, ?MODULE, list, [Bindings, Params]) of
        {badrpc, Reason} -> {error, Reason};
        Res -> Res
    end.

lookup(#{node := Node, clientid := ClientId}, _Params) ->
    {ok, #{items => format(emq_mgmt:lookup_client(Node, ClientId))}};

lookup(#{clientid := ClientId}, _Params) ->
    {ok, #{items => format(emq_mgmt:lookup_client(ClientId))}}.

kickout(#{clientid := ClientId}, _Params) ->
    emq_mgmt:kickout_client(ClientId).

clean_acl_cache(#{clientid := ClientId}, Params) ->
    Topic = proplists:get_value(<<"topic">>, Params),
    emq_mgmt:clean_acl_cache(ClientId, Topic);

format(Clients) when is_list(Clients) ->
    [format(Client) || Client <- Clients];

format(#mqtt_client{client_id    = ClientId,
                    peername     = {IpAddr, Port},
                    username     = Username,
                    clean_sess   = CleanSess,
                    proto_ver    = ProtoVer,
                    keepalive    = KeepAlvie,
                    connected_at = ConnectedAt}) ->
    #{client_id    => ClientId,
      username     => Username,
      ipaddress    => iolist_to_binary(ntoa(IpAddr)),
      port         => Port,
      clean_sess   => CleanSess,
      proto_ver    => ProtoVer,
      keepalive    => KeepAlvie,
      connected_at => iolist_to_binary(strftime(ConnectedAt))}.

