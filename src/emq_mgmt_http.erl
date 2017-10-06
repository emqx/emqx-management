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

-module(emq_mgmt_http).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_internal.hrl").

-import(proplists, [get_value/2, get_value/3]).

-export([start_listeners/0, stop_listeners/0, rest_handler/0]).

-export([client/3, client_list/3, client_list/4, kick_client/3, clean_acl_cache/3]).
-export([route/3, route_list/2]).
-export([session/3, session_list/3, session_list/4]).
-export([subscription/3, subscription_list/3, subscription_list/4]).
-export([nodes/2, node/3, brokers/2, broker/3, listeners/2, listener/3, metrics/2, metrics/3, stats/2, stats/3]).
-export([publish/2, subscribe/2, unsubscribe/2]).
-export([plugin_list/3, enabled/4]).
-export([modify_config/3, modify_config/4, config_list/2, config_list/3,
         plugin_config_list/4, modify_plugin_config/4]).

%%--------------------------------------------------------------------
%% Start/Stop Listeners
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun start_listener/1, listeners()).
    
stop_listeners() ->
    lists:foreach(fun stop_listener/1, listeners()).

start_listener({Proto, Port, Options}) when Proto == http orelse Proto == https ->
    mochiweb:start_http(listener_name(Proto), Port, Options, rest_handler()).

stop_listener({Proto, Port, _}) ->
    mochiweb:stop_http(listener_name(Proto), Port).

listeners() ->
    application:get_env(emq_management, listeners, []).
    
listener_name(Proto) ->
    list_to_atom("management:" ++ atom_to_list(Proto)).

%%--------------------------------------------------------------------
%% REST Handler and Dispatcher
%%--------------------------------------------------------------------

rest_handler() ->
    {?MODULE, handle_request, [dispatcher()]}.

dispatcher() ->
    dispatcher(api_list()).

api_list() ->
    [#{method => Method, path => Path, reg => Reg, function => Fun, args => Args}
      || {http_api, [{Method, Path, Reg, Fun, Args}]} <- emqttd_rest:module_info(attributes)].

%%--------------------------------------------------------------------
%% REST API
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------------
%% management/monitoring
%%--------------------------------------------------------------------------
nodes('GET', _Params) ->
    Data = emqttd_mgmt:nodes_info(),
    {ok, Data}.

node('GET', _Params, Node) ->
    Data = emqttd_mgmt:node_info(l2a(Node)),
    {ok, Data}.

brokers('GET', _Params) ->
    Data = emqttd_mgmt:brokers(),
    {ok, [format_broker(Node, Broker) || {Node, Broker} <- Data]}.

broker('GET', _Params, Node) ->
    Data = emqttd_mgmt:broker(l2a(Node)),
    {ok, format_broker(Data)}.

listeners('GET', _Params) ->
    Data = emqttd_mgmt:listeners(),
    {ok, [[{Node, format_listeners(Listeners, [])} || {Node, Listeners} <- Data]]}.

listener('GET', _Params, Node) ->
    Data = emqttd_mgmt:listener(l2a(Node)),
    {ok, [format_listener(Listeners) || Listeners <- Data]}.

metrics('GET', _Params) ->
    Data = emqttd_mgmt:metrics(),
    {ok, [Data]}.

metrics('GET', _Params, Node) ->
    Data = emqttd_mgmt:metrics(l2a(Node)),
    {ok, Data}.

stats('GET', _Params) ->
    {ok, [emqttd_mgmt:stats()]}.

stats('GET', _Params, Node) ->
    {ok, emqttd_mgmt:stats(l2a(Node))}.

format_broker(Node, Broker) ->
    OtpRel  = "R" ++ erlang:system_info(otp_release) ++ "/" ++ erlang:system_info(version),
    [{name,     Node},
     {version,  bin(get_value(version, Broker))},
     {sysdescr, bin(get_value(sysdescr, Broker))},
     {uptime,   bin(get_value(uptime, Broker))},
     {datetime, bin(get_value(datetime, Broker))},
     {otp_release, l2b(OtpRel)},
     {node_status, 'Running'}].

format_broker(Broker) ->
    OtpRel  = "R" ++ erlang:system_info(otp_release) ++ "/" ++ erlang:system_info(version),
    [{version,  bin(get_value(version, Broker))},
     {sysdescr, bin(get_value(sysdescr, Broker))},
     {uptime,   bin(get_value(uptime, Broker))},
     {datetime, bin(get_value(datetime, Broker))},
     {otp_release, l2b(OtpRel)},
     {node_status, 'Running'}].

format_listeners([], Acc) ->
    Acc;
format_listeners([{Protocol, ListenOn, Info}| Listeners], Acc) ->
    format_listeners(Listeners, [format_listener({Protocol, ListenOn, Info}) | Acc]).

format_listener({Protocol, ListenOn, Info}) ->
    Listen = l2b(esockd:to_string(ListenOn)),
    lists:append([{protocol, Protocol}, {listen, Listen}], Info).

%%--------------------------------------------------------------------------
%% mqtt
%%--------------------------------------------------------------------------

%%--------------------------------------------------------------------------
%% plugins
%%--------------------------------------------------------------------------

return(Result) ->
    case Result of
        ok ->
            {ok, []};
        {ok, _} ->
            {ok, []};
        {error, already_started} ->
            {error, [{code, ?ERROR10}, {message, <<"already_started">>}]};
        {error, not_started} ->
            {error, [{code, ?ERROR11}, {message, <<"not_started">>}]};
        Error ->
            lager:error("error:~p", [Error]),
            {error, [{code, ?ERROR2}, {message, <<"unknown">>}]}
    end.
plugin(#mqtt_plugin{name = Name, version = Ver, descr = Descr,
                    active = Active}) ->
    [{name, Name},
     {version, iolist_to_binary(Ver)},
     {description, iolist_to_binary(Descr)},
     {active, Active}].

%%--------------------------------------------------------------------------
%% modify config
%%--------------------------------------------------------------------------
modify_config('PUT', Params, App) ->
    Key   = get_value(<<"key">>, Params, <<"">>),
    Value = get_value(<<"value">>, Params, <<"">>),
    case emqttd_mgmt:modify_config(l2a(App), b2l(Key), b2l(Value)) of
        true  -> {ok, []};
        false -> {error, [{code, ?ERROR2}]}
    end.

modify_config('PUT', Params, Node, App) ->
    Key   = get_value(<<"key">>, Params, <<"">>),
    Value = get_value(<<"value">>, Params, <<"">>),
    case emqttd_mgmt:modify_config(l2a(Node), l2a(App), b2l(Key), b2l(Value)) of
        ok  -> {ok, []};
        _ -> {error, [{code, ?ERROR2}]}
    end.

config_list('GET', _Params) ->
    Data = emqttd_mgmt:get_configs(),
    {ok, [{Node, format_config(Config, [])} || {Node, Config} <- Data]}.

config_list('GET', _Params, Node) ->
    Data = emqttd_mgmt:get_config(l2a(Node)),
    {ok, [format_config(Config) || Config <- lists:reverse(Data)]}.

plugin_config_list('GET', _Params, Node, App) ->
    {ok, Data} = emqttd_mgmt:get_plugin_config(l2a(Node), l2a(App)),
    {ok, [format_plugin_config(Config) || Config <- lists:reverse(Data)]}.

modify_plugin_config('PUT', Params, Node, App) ->
    PluginName = l2a(App),
    case emqttd_mgmt:modify_plugin_config(l2a(Node), PluginName, Params) of
        ok  ->
            Plugins = emqttd_plugins:list(),
            {_, _, _, _, Status} = lists:keyfind(PluginName, 2, Plugins),
            case Status of
                true  ->
                    emqttd_plugins:unload(PluginName),
                    timer:sleep(500),
                    emqttd_plugins:load(PluginName),
                    {ok, []};
                false ->
                    {ok, []}
            end;
        _ ->
            {error, [{code, ?ERROR2}]}
    end.


format_config([], Acc) ->
    Acc;
format_config([{Key, Value, Datatpye, App}| Configs], Acc) ->
    format_config(Configs, [format_config({Key, Value, Datatpye, App}) | Acc]).

format_config({Key, Value, Datatpye, App}) ->
    [{<<"key">>, l2b(Key)},
     {<<"value">>, l2b(Value)},
     {<<"datatpye">>, l2b(Datatpye)},
     {<<"app">>, App}].

format_plugin_config({Key, Value, Desc, Required}) ->
    [{<<"key">>, l2b(Key)},
     {<<"value">>, l2b(Value)},
     {<<"desc">>, l2b(Desc)},
     {<<"required">>, Required}].

%%--------------------------------------------------------------------------
%% Admin
%%--------------------------------------------------------------------------
auth('POST', Params) ->
    Username = get_value(<<"username">>, Params),
    Password = get_value(<<"password">>, Params),
    case emqttd_mgmt:check_user(Username, Password) of
        ok ->
            {ok, []};
        {error, Reason} ->
            {error, [{code, ?ERROR3}, {message, list_to_binary(Reason)}]}
    end.

users('POST', Params) ->
    Username = get_value(<<"username">>, Params),
    Password = get_value(<<"password">>, Params),
    Tag = get_value(<<"tags">>, Params),
    code(emqttd_mgmt:add_user(Username, Password, Tag));

users('GET', _Params) ->
    {ok, [Admin || Admin <- emqttd_mgmt:user_list()]}.

users('GET', _Params, Username) ->
    {ok, emqttd_mgmt:lookup_user(list_to_binary(Username))};

users('PUT', Params, Username) ->
    code(emqttd_mgmt:update_user(list_to_binary(Username), Params));

users('DELETE', _Params, "admin") ->
    {error, [{code, ?ERROR6}, {message, <<"admin cannot be deleted">>}]};
users('DELETE', _Params, Username) ->
    code(emqttd_mgmt:remove_user(list_to_binary(Username))).

change_pwd('PUT', Params, Username) ->
    OldPwd = get_value(<<"old_pwd">>, Params),
    NewPwd = get_value(<<"new_pwd">>, Params),
    code(emqttd_mgmt:change_password(list_to_binary(Username), OldPwd, NewPwd)).

code(ok)             -> {ok, []};
code(error)          -> {error, [{code, ?ERROR2}]};
code({error, Error}) -> {error, Error}.
%%--------------------------------------------------------------------------
%% Inner function
%%--------------------------------------------------------------------------
format(created_at, Val) ->
    l2b(strftime(Val));
format(_, Val) ->
    Val.



