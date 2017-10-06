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

-module(emq_mgmt_api_brokers).

-author("Feng Lee <feng@emqtt.io>").

-rest_api(#{name   => list_brokers_info,
            method => 'GET',
            path   => "/brokers/",
            func   => list,
            descr  => "A list of brokers in the cluster"}).

-rest_api(#{name   => list_broker_info,
            method => 'GET',
            path   => "/brokers/:node",
            func   => list,
            descr  => "Show broker info of a node"}).

list(#{node := Node}, _Params) ->
    {ok, format(emq_mgmt:broker_info(list_to_atom(Node)))}.

list(_Bindings, _Params) ->
    {ok, [{Node, format(Info)} || {Node, Info} <- emq_mgmt:brokers_info()]}.

format({error, Reason}) -> [{error, Reason}];

format(Info) -> Info.

