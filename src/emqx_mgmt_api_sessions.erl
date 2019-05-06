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

-module(emqx_mgmt_api_sessions).

-include_lib("emqx/include/emqx.hrl").

-import(minirest, [return/1]).

-rest_api(#{name   => list_sessions,
            method => 'GET',
            path   => "/sessions/",
            func   => list,
            descr  => "A list of sessions in the cluster"}).

-rest_api(#{name   => list_node_sessions,
            method => 'GET',
            path   => "nodes/:atom:node/sessions/",
            func   => list,
            descr  => "A list of sessions on a node"}).

-rest_api(#{name   => lookup_session,
            method => 'GET',
            path   => "/sessions/:bin:clientid",
            func   => lookup,
            descr  => "Lookup a session in the cluster"}).

-rest_api(#{name   => lookup_node_session,
            method => 'GET',
            path   => "nodes/:atom:node/sessions/:bin:clientid",
            func   => lookup,
            descr  => "Lookup a session on the node"}).

-rest_api(#{name   => clean_presisent_session,
            method => 'DELETE',
            path   => "/sessions/persistent/:bin:clientid",
            func   => clean,
            descr  => "Clean a persistent session in the cluster"}).

-rest_api(#{name   => clean_node_presisent_session,
            method => 'DELETE',
            path   => "nodes/:atom:node/sessions/persistent/:bin:clientid",
            func   => clean,
            descr  => "Clean a persistent session on the node"}).

-export([ list/2
        , lookup/2
        , clean/2
        ]).

list(Bindings, Params) when map_size(Bindings) =:= 0 ->
    %%TODO: across nodes?
    list(#{node => node()}, Params);

list(#{node := Node}, Params) when Node =:= node() ->
    return({ok, emqx_mgmt_api:paginate(emqx_session, Params, fun format/1)});

list(Bindings = #{node := Node}, Params) ->
    case rpc:call(Node, ?MODULE, list, [Bindings, Params]) of
        {badrpc, Reason} -> return({error, Reason});
        Res -> Res
    end.

lookup(#{node := Node, clientid := ClientId}, _Params) ->
    return({ok, format(emqx_mgmt:lookup_session(Node, http_uri:decode(ClientId)))});

lookup(#{clientid := ClientId}, _Params) ->
    return({ok, format(emqx_mgmt:lookup_session(http_uri:decode(ClientId)))}).

clean(#{node := Node, clientid := ClientId}, _Params) ->
    return(emqx_mgmt:clean_session(Node, http_uri:decode(ClientId)));

clean(#{clientid := ClientId}, _Params) ->
    return(emqx_mgmt:clean_session(http_uri:decode(ClientId))).

format([]) ->
    [];
format(Items) when is_list(Items) ->
    [format(Item) || Item <- Items];

format(Key) when is_tuple(Key) ->
    format(emqx_mgmt:item(session, Key));

format(Item = #{created_at := CreatedAt}) ->
    Item1 = maps:remove(client_pid, Item),
    Item1#{node => node(), created_at => iolist_to_binary(emqx_mgmt_util:strftime(CreatedAt))}.

