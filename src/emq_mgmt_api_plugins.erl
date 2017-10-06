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

-module(emq_mgmt_api_plugins).

-author("Feng Lee <feng@emqtt.io>").

-rest_api(#{name   => list_all_plugins,
            method => 'GET',
            path   => "/plugins/",
            func   => list,
            descr  => "List all plugins in the cluster"}).

-rest_api(#{name   => list_node_plugins,
            method => 'GET',
            path   => "/nodes/:node/plugins/",
            func   => list,
            descr  => "List all plugins on a node"}).

-rest_api(#{name   => load_plugin,
            method => 'POST',
            path   => "/nodes/:node/plugins/:plugin/load",
            func   => load,
            descr  => "Load a plugin"}).

-rest_api(#{name   => unload_plugin,
            method => 'post',
            path   => "/nodes/:node/plugins/:plugin/unload",
            func   => unload,
            descr  => "Unload a plugin"}).

list(#{node := Node}, _Params) ->
    {ok, emq_mgmt:plugins(atom(Node))}.

list(_Bindings, _Params) ->
    {ok, emq_mgmt:plugins()}.

load(#{node := Node, plugin := Plugin}, _Params) ->
    emq_mgmt:load_plugin(atom(Node), atom(Plugin)).

unload(#{node := Node, plugin := Plugin}, _Params) ->
    emq_mgmt:unload_plugin(atom(Node), atom(Plugin)).
    
atom(S) -> list_to_existing_atom(S).

