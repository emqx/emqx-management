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

-module(emq_mgmt_api_nodes).

-author("Feng Lee <feng@emqtt.io>").

-rest_api(#{name   => list_nodes,
            method => 'GET',
            path   => "/nodes/",
            func   => list,
            descr  => "A list of nodes in the cluster"}).

-rest_api(#{name   => lookup_node,
            method => 'GET',
            path   => "/nodes/:node",
            func   => lookup,
            descr  => "Lookup a node in the cluster"}).

-export([list/2, lookup/2]).

list(_Bindings, _Params) ->
    {ok, [{Node, format(Info)} || {Node, Info} <- emq_mgmt:list_nodes()]}.

lookup(#{node := Node}, _Params) ->
    {ok, emq_mgmt:lookup_node(Node)}.

format({error, Reason}) -> [{error, Reason}];

format(Info = #{memory_total := Total, memory_used := Used}) ->
    Info#{memory_total := emq_mgmt_util:kmg(Total),
          memory_used  := emq_mgmt_util:kmg(Used)}.

