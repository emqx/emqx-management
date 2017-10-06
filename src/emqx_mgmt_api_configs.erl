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

-module(emqx_mgmt_api_configs).

-author("Feng Lee <feng@emqtt.io>").

-include("emqx_mgmt.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-import(proplists, [get_value/2, get_value/3]).

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

-export([get_configs/2, update_config/2, get_plugin_configs/2, update_plugin_configs/2]).

get_configs(#{node := Node}, _Params) ->
    {ok, format(emqx_mgmt:get_all_configs(Node))};

get_configs(_Binding, _Params) ->
    {ok, [{Node, format(Configs)} || {Node, Configs} <- emqx_mgmt:get_all_configs()]}.

update_config(#{node := Node, app := App}, Params) ->
    Key   = get_value(<<"key">>, Params),
    Value = get_value(<<"value">>, Params),
    emqx_mgmt:update_config(Node, App, Key, Value);

update_config(#{app := App}, Params) ->
    Key   = get_value(<<"key">>, Params),
    Value = get_value(<<"value">>, Params),
    emqx_mgmt:update_config(App, Key, Value).

get_plugin_configs(#{node := Node, plugin := Plugin}, _Params) ->
    {ok, [ format_plugin_config(Config) 
           || Config <- emqx_mgmt:get_plugin_configs(Node, Plugin) ]}.

update_plugin_configs(#{node := Node, plugin := Plugin}, Params) ->
    case emqx_mgmt:update_plugin_configs(Node, Plugin, Params) of
        ok  ->
            ensure_reload_plugin(Plugin);
        _ ->
            {error, [{code, ?ERROR2}]}
    end.

ensure_reload_plugin(Plugin) ->
    case lists:keyfind(Plugin, 2, emqttd_plugins:list()) of
        {_, _, _, _, true} ->
            emqttd_plugins:unload(Plugin),
            timer:sleep(500),
            emqttd_plugins:load(Plugin);
         _ ->
            ok
    end.

format(Configs) when is_list(Configs) ->
    format(Configs, []);
format({Key, Value, Datatpye, App}) ->
    [{<<"key">>, list_to_binary(Key)},
     {<<"value">>, list_to_binary(Value)},
     {<<"datatpye">>, list_to_binary(Datatpye)},
     {<<"app">>, App}].

format([], Acc) ->
    Acc;
format([{Key, Value, Datatpye, App}| Configs], Acc) ->
    format(Configs, [format({Key, Value, Datatpye, App}) | Acc]).

format_plugin_config({Key, Value, Desc, Required}) ->
    [{<<"key">>, list_to_binary(Key)},
     {<<"value">>, list_to_binary(Value)},
     {<<"desc">>, list_to_binary(Desc)},
     {<<"required">>, Required}].

