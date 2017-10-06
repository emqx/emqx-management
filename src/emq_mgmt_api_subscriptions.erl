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

-module(emq_mgmt_api_subscriptions).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("emqttd/include/emqttd.hrl").

-rest_api(#{name   => list_node_subscriptions,
            method => 'GET',
            path   => "/nodes/:node/subscriptions/",
            func   => list,
            descr  => "A list of subscriptions on a node"}).

-rest_api(#{name   => lookup_client_subscriptions,
            method => 'GET',
            path   => "/subscriptions/:clientid",
            func   => lookup,
            descr  => "A list of subscriptions of a client"}).

-rest_api(#{name   => lookup_client_subscriptions_with_node,
            method => 'GET',
            path   => "/nodes/:node/subscriptions/:clientid",
            func   => lookup,
            descr  => "A list of subscriptions of a client on the node"}).

list(#{node := Node}, Params) when Node =:= node() ->
    {ok, emq_mgmt_api:paginate(emq_mgmt:query_handle(subscriptions),
                               emq_mgmt:count(subscriptions),
                               Params, fun format/1)}.

lookup(#{node := Node, clientid := ClientId}, Params) ->
    {ok, #{items => format(emq_mgmt:lookup_subscriptions(Node, ClientId))}};

lookup(#{clientid := ClientId}, Params) ->
    {ok, #{items => format(emq_mgmt:lookup_subscriptions(ClientId))}}.

format(Items) ->
    [format(Item) || Item <- Items];

format(#{topic := Topic, clientid := ClientId, options := Options}) ->
    QoS = proplists:get_value(qos, Options),
    [{topic, Topic}, {client_id, maybe_to_binary(ClientId}, {qos, QoS}].

maybe_to_binary(ClientId) when is_pid(ClientId) ->
    list_to_binary(pid_to_list(ClientId));

maybe_to_binary(ClientId) ->
    ClientId.

