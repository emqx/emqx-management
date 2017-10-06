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

-module(emq_mgmt_api_sessions).

-include_lib("emqttd/include/emqttd.hrl").

-rest_api(#{name   => list_node_sessions,
            method => 'GET',
            path   => "nodes/:node/sessions/",
            func   => list,
            descr  => "A list of sessions on a node"}).

-rest_api(#{name   => lookup_node_session,
            method => 'GET',
            path   => "nodes/:node/sessions/:clientid",
            func   => lookup,
            descr  => "Lookup a session on the node"}).

-rest_api(#{name   => lookup_session,
            method => 'GET',
            path   => "nodes/:node/sessions/:clientid",
            func   => lookup,
            descr  => "Lookup a session in the cluster"}).

list(#{node := Node}, Params) when Node =:= node() ->
    {ok, emq_mgmt_api:paginate(emq_mgmt:query_handle(sessions),
                               emq_mgmt:count(sessions),
                               Params, fun format/1)};

list(Bindings = #{node := Node}, Params) ->
    case rpc:call(Node, ?MODULE, list, [Bindings, Params]) of
        {badrpc, Reason} -> {error, Reason};
        Res -> Res
    end.

lookup(#{node := Node, clientid := ClientId}, _Params) ->
    {ok, #{items => format(emq_mgmt:lookup_session(Node, ClientId))}};

lookup(#{clientid := ClientId}, _Params) ->
    {ok, #{items => format(emq_mgmt:lookup_session(ClientId))}}.

format({ClientId, _Pid, Persistent, Properties}) ->
    format(emq_mgmt:item(session, Item));

format(Items) when is_list(Items) ->
    [format(Item) || Item <- Items];

format(Item = #{created_at = CreatedAt}) ->
    Item#{created_at = iolist_to_binary(emq_mgmt_util:strftime(CreatedAt))}.

