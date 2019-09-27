%%--------------------------------------------------------------------
%% Copyright (c) 2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_api_pubsub).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").
-include("emqx_mgmt.hrl").

-import(proplists, [ get_value/2
                   , get_value/3
                   ]).

-import(minirest, [  return/1 ]).

-rest_api(#{name   => mqtt_subscribe,
            method => 'POST',
            path   => "/mqtt/subscribe",
            func   => subscribe,
            descr  => "Subscribe a topic"}).

-rest_api(#{name   => mqtt_batch_subscribes,
        method => 'POST',
        path   => "/mqtt/batch_subscribe",
        func   => batch_subscribe,
        descr  => "Batch subscribes a topic"}).

-rest_api(#{name   => mqtt_publish,
            method => 'POST',
            path   => "/mqtt/publish",
            func   => publish,
            descr  => "Publish a MQTT message"}).

-rest_api(#{name   => mqtt_batch_publishs,
            method => 'POST',
            path   => "/mqtt/batch_publish",
            func   => batch_publish,
            descr  => "Batch publish a MQTT message"}).

-rest_api(#{name   => mqtt_unsubscribe,
            method => 'POST',
            path   => "/mqtt/unsubscribe",
            func   => unsubscribe,
            descr  => "Unsubscribe a topic"}).

-rest_api(#{name   => mqtt_batch_unsubscribes,
            method => 'POST',
            path   => "/mqtt/batch_unsubscribe",
            func   => batch_unsubscribe,
            descr  => "Batch unsubscribes a topic"}).

-export([ subscribe/2
        , publish/2
        , unsubscribe/2
        , batch_subscribe/2
        , batch_publish/2
        , batch_unsubscribe/2
        ]).

subscribe(_Bindings, Params) ->
    {ClientId, Topic, QoS} = parsing_params(subscribe, Params),
    Reason = do(subscribe, {ClientId, Topic, QoS}),
    io:format("Reason: ~p~n", [Reason]),
    return(Reason).

batch_subscribe(_Bindings, Params) ->
    case Params =/= [] of
        true ->
            Reason = loop(subscribe, Params, []),
            return({ok, Reason});
        false ->
            return({ok, ?ERROR15, bad_topic})
    end.

publish(_Bindings, Params) ->
    {ClientId, Topic, Qos, Retain, Payload} = parsing_params(publish, Params),
    Reason = do(publish, {ClientId, Topic, Qos, Retain, Payload}),
    return(Reason).

batch_publish(_Bindings, Params) ->
    case Params =/= [] of
        true ->
            Reason = loop(publish, Params, []),
            return({ok, Reason});
        false ->
            return({ok, ?ERROR15, bad_topic})
    end.

unsubscribe(_Bindings, Params) ->
    {ClientId, Topic} = parsing_params(unsubscribe, Params),
    Reason = do(unsubscribe, {ClientId, Topic}),
    return(Reason).

batch_unsubscribe(_Bindings, Params) ->
    case Params =/= [] of
        true ->
            Reason = loop(unsubscribe, Params, []),
            return({ok, Reason});
        false ->
            return({ok, ?ERROR15, bad_topic})
    end.

parsing_params(subscribe, Params) ->
    logger:debug("API subscribe Params:~p", [Params]),
    ClientId = get_value(<<"client_id">>, Params),
    Topics   = topics(filter, get_value(<<"topic">>, Params), get_value(<<"topics">>, Params, <<"">>)),
    QoS      = get_value(<<"qos">>, Params, 0),
    {ClientId, Topics, QoS};

parsing_params(publish, Params) ->
    logger:debug("API publish Params:~p", [Params]),
    Topics   = topics(name, get_value(<<"topic">>, Params), get_value(<<"topics">>, Params, <<"">>)),
    ClientId = get_value(<<"client_id">>, Params),
    Payload  = get_value(<<"payload">>, Params, <<>>),
    Qos      = get_value(<<"qos">>, Params, 0),
    Retain   = get_value(<<"retain">>, Params, false),
    {ClientId, Topics, Qos, Retain, Payload};

parsing_params(unsubscribe, Params) ->
    logger:debug("API unsubscribe Params:~p", [Params]),
    ClientId = get_value(<<"client_id">>, Params),
    Topic    = get_value(<<"topic">>, Params),
    {ClientId, Topic}.

do(subscribe, Data) ->
    {ClientId, Topics, QoS} = Data,
    case Topics =/= [] of
        true ->
            TopicTable = parse_topic_filters(Topics, QoS),
            case emqx_mgmt:subscribe(ClientId, TopicTable) of
                {error, Reason} -> 
                    {ok, ?ERROR12, Reason};
                _ ->
                    ok
            end;
        false ->
            {ok, ?ERROR15, bad_topic}
    end;

do(publish, Data) ->
    {ClientId, Topics, Qos, Retain, Payload} = Data,
    case Topics =/= [] of
        true ->
            lists:foreach(fun(Topic) ->
                Msg = emqx_message:make(ClientId, Qos, Topic, Payload),
                emqx_mgmt:publish(Msg#message{flags = #{retain => Retain}})
            end, Topics),
            ok;
        false ->
            {ok, ?ERROR15, bad_topic}
    end;

do(unsubscribe, Data) ->
    {ClientId, Topic} = Data,
    case validate_by_filter(Topic) of
        true ->
            case emqx_mgmt:unsubscribe(ClientId, Topic) of
                {error, Reason} -> 
                    ({ok, ?ERROR12, Reason});
                _ -> 
                    ok
            end;
        false ->
            ({ok, ?ERROR15, bad_topic})
    end.

loop(_ ,[], Reason) -> Reason;

loop(subscribe, [Params | T], Reason) ->
    {ClientId, Topic, QoS} = parsing_params(subscribe, Params),
    case do(subscribe, {ClientId, Topic, QoS}) of
        ok -> ReasonCode = 0;
        Other -> {_, ReasonCode, _} = Other
    end,
    R = [
        {client_id, ClientId},
        {topic, Topic},
        {qos, QoS},
        {reason_code, ReasonCode}
    ],
    loop(subscribe, T, Reason ++ [R]);

loop(publish, [Params | T], Reason) ->
    {ClientId, Topic, Qos, Retain, Payload} = parsing_params(publish, Params),
    case do(publish, {ClientId, Topic, Qos, Retain, Payload}) of
        ok -> ReasonCode = 0;
        Other -> {_, ReasonCode, _} = Other
    end,
    R = [
        {client_id, ClientId},
        {topic, Topic},
        {qos, Qos},
        {retain, Retain},
        {payload, Payload},
        {reason_code, ReasonCode}
    ],
    loop(publish, T, Reason ++ [R]);

loop(unsubscribe, [Params | T], Reason) ->
    {ClientId, Topic} = parsing_params(unsubscribe, Params),
    case do(unsubscribe, {ClientId, Topic}) of
        ok -> ReasonCode = 0;
        Other -> {_, ReasonCode, _} = Other
    end,
    R = [
        {client_id, ClientId},
        {topic, Topic},
        {reason_code, ReasonCode}
    ],
    loop(unsubscribe, T, Reason ++ [R]).

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

