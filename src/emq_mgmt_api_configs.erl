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

-module(emq_mgmt_api_configs).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("emqttd/include/emqttd.hrl").

-rest_api(#{name   => get_all_configs,
            method => 'GET',
            path   => "/configs/",
            func   => get_configs,
            descr  => "Get all configs"}).

-rest_api(#{name   => get_all_configs,
            method => 'GET',
            path   => "/nodes/:node/configs/",
            func   => get_configs,
            descr  => "Get all configs of a node"}).

-rest_api(#{name   => update_config,
            method => 'PUT',
            path   => "/configs/:app",
            func   => update_config,
            descr  => "Update config of an application in the cluster"}).

-rest_api(#{name   => update_node_config,
            method => 'PUT',
            path   => "/nodes/:node/configs/:app",
            func   => update_config,
            descr  => "Update config of an application on a node"}).

-rest_api(#{name   => get_plugin_configs,
            method => 'GET',
            path   => "/nodes/:node/plugin_configs/:plugin",
            func   => get_plugin_configs,
            descr  => "Get configurations of a plugin on the node"}).

-rest_api(#{name   => update_plugin_configs,
            method => 'PUT',
            path   => "/nodes/:node/plugin_configs/:plugin",
            func   => update_plugin_configs,
            descr  => "Update configurations of a plugin on the node"}).

get_configs(#{node := Node}, _Params) ->
    {ok, emq_mgmt:get_all_configs(Node)};

get_configs(_Binding, _Params) ->
    {ok, emq_mgmt:get_all_configs()}.

update_config(#{node := Node, app := App}, Params) ->
    Key   = get_value(<<"key">>, Params),
    Value = get_value(<<"value">>, Params),
    emq_mgmt:update_config(Node, App, Key, Value);

update_config(#{app := App}, Params) ->
    Key   = get_value(<<"key">>, Params),
    Value = get_value(<<"value">>, Params),
    emq_mgmt:update_config(App, Key, Value).

get_plugin_configs(#{node := Node, plugin := Plugin}, _Params) ->
    {ok, [ format_plugin_config(Config) 
           || Config <- emq_mgmt:get_plugin_configs(Node, Plugin) ]}.

update_plugin_configs(#{node := Node, plugin := Plugin}, Params) ->
    case emq_mgmt:update_plugin_configs(Node, Plugin, Params) of
        ok  ->
            ensure_reload_plugin(Plugin);
        _ ->
            {error, [{code, ?ERROR2}]}
    end.

ensure_reload_plugin(Plugin) ->
    case lists:keyfind(Plugin, 2, emqttd_plugins:list()) of
        {_, _, _, _, true} ->
            emqttd_plugins:unload(PluginName),
            timer:sleep(500),
            emqttd_plugins:load(PluginName);
         _ ->
            ok
    end.

