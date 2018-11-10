%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_api_pubsub).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include("emqx_mgmt.hrl").

-import(proplists, [get_value/2, get_value/3]).

-rest_api(#{name   => mqtt_subscribe,
            method => 'POST',
            path   => "/mqtt/subscribe",
            func   => subscribe,
            descr  => "Subscribe a topic"}).

-rest_api(#{name   => mqtt_publish,
            method => 'POST',
            path   => "/mqtt/publish",
            func   => publish,
            descr  => "Publish a MQTT message"}).

-rest_api(#{name   => mqtt_unsubscribe,
            method => 'POST',
            path   => "/mqtt/unsubscribe",
            func   => unsubscribe,
            descr  => "Unsubscribe a topic"}).

-export([subscribe/2, publish/2, unsubscribe/2]).

subscribe(_Bindings, Params) ->
    logger:debug("API subscribe Params:~p", [Params]),
    ClientId = get_value(<<"client_id">>, Params),
    Topics   = topics(filter, get_value(<<"topic">>, Params), get_value(<<"topics">>, Params, <<"">>)),
    QoS      = get_value(<<"qos">>, Params, 0),
    case Topics =/= [] of
        true ->
            TopicTable = parse_topic_filters(Topics, QoS),
            case emqx_mgmt:subscribe(ClientId, TopicTable) of
                {error, _Reson} -> {ok, #{code => ?ERROR12}};
                _ -> {ok, #{code => 0}}
            end;
        false ->
            {ok, #{code => ?ERROR15}}
    end.

publish(_Bindings, Params) ->
    logger:debug("API publish Params:~p", [Params]),
    Topics   = topics(name, get_value(<<"topic">>, Params), get_value(<<"topics">>, Params, <<"">>)),
    ClientId = get_value(<<"client_id">>, Params),
    Payload  = get_value(<<"payload">>, Params, <<>>),
    Qos      = get_value(<<"qos">>, Params, 0),
    Retain   = get_value(<<"retain">>, Params, false),
    case Topics =/= [] of
        true ->
            lists:foreach(fun(Topic) ->
                Msg = emqx_message:make(ClientId, Qos, Topic, Payload),
                emqx_mgmt:publish(Msg#message{flags = #{retain => Retain}})
            end, Topics),
            {ok, #{code => 0}};
        false ->
            {ok, #{code => ?ERROR15}}
    end.

unsubscribe(_Bindings, Params) ->
    logger:debug("API unsubscribe Params:~p", [Params]),
    ClientId = get_value(<<"client_id">>, Params),
    Topic    = get_value(<<"topic">>, Params),
    case validate_by_filter(Topic) of
        true ->
            case emqx_mgmt:unsubscribe(ClientId, Topic) of
                {error, _} -> {ok, #{code => ?ERROR12}};
                _ -> {ok, #{code => 0}}
            end;
        false ->
            {ok, #{code => ?ERROR15}}
    end.

topics(Type, undefined, Topics0) ->
    Topics = binary:split(Topics0, <<",">>, [global]),
    case Type of
        name -> lists:filter(fun(T) -> validate_by_name(T) end, Topics);
        filter -> lists:filter(fun(T) -> validate_by_filter(T) end, Topics)
    end;

topics(Type, Topic, _) ->
    topics(Type, undefined, Topic).

%%TODO:
% validate(qos, Qos) ->
%    (Qos >= ?QOS_0) and (Qos =< ?QOS_2).

validate_by_filter(Topic) ->
    emqx_topic:validate({filter, Topic}).

validate_by_name(Topic) ->
    emqx_topic:validate({name, Topic}).

parse_topic_filters(Topics, Qos) ->
    [begin
         {Topic, Opts} = emqx_topic:parse(Topic0),
         {Topic, Opts#{qos => Qos}}
     end || Topic0 <- Topics].

