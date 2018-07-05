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

-module(emqx_mgmt_api_pubsub).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("emqx/include/emqx.hrl").

-include_lib("emqx/include/emqx_mqtt.hrl").

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

-rest_api(#{name   => dmp_publish,
            method => 'POST',
            path   => "/dmp/publish",
            func   => dmp_publish,
            descr  => "DMP Publish a MQTT message for Device"}).

-rest_api(#{name   => mqtt_unsubscribe,
            method => 'POST',
            path   => "/mqtt/unsubscribe",
            func   => unsubscribe,
            descr  => "Unsubscribe a topic"}).

-export([subscribe/2, publish/2, dmp_publish/2, unsubscribe/2]).

subscribe(_Bindings, Params) ->
    ClientId = get_value(<<"client_id">>, Params),
    Topic    = get_value(<<"topic">>, Params),
    QoS      = get_value(<<"qos">>, Params, 0),
    emqx_mgmt:subscribe(ClientId, Topic, QoS).

publish(_Bindings, Params) ->
    Topics   = topics(Params),
    ClientId = get_value(<<"client_id">>, Params),
    Payload  = get_value(<<"payload">>, Params, <<>>),
    Qos      = get_value(<<"qos">>, Params, 0),
    Retain   = get_value(<<"retain">>, Params, false),
    lists:foreach(fun(Topic) ->
        Msg = emqx_message:make(ClientId, Qos, Topic, Payload),
        emqx_mgmt:publish(Msg#mqtt_message{retain = Retain})
    end, Topics).

dmp_publish(_Bindings, Params) ->
    case check_required_params(Params) of
    ok ->
        make_publish(Params),
        {ok, [{code, 0}, {message, <<>>}]};
    {error, Error} ->
        {ok, [{code, 1}, {message, list_to_binary(Error)}]}
    end.

make_publish(Params) ->
    Qos      = get_value(<<"qos">>, Params, 1),
    Url      = get_value(<<"callback">>, Params),
    Payload  = get_value(<<"payload">>, Params),
    AppId    = get_value(<<"app_id">>, Params, <<"DMP">>),
    TaskId   = get_value(<<"task_id">>, Params),
    DataType = get_value(<<"data_type">>, Params, 1),
    Topic    = mountpoint(Params),
    Msg      = emqx_message:make(AppId, Qos, Topic, Payload, [{<<"url">>, Url},
                                                              {<<"task_id">>, TaskId},
                                                              {<<"return_filed">>,[<<"task_id">>]},
                                                              {<<"data_type">>, DataType}]),
    emqx_mgmt:publish(Msg).

unsubscribe(_Bindings, Params) ->
    ClientId = get_value(<<"client_id">>, Params),
    Topic    = get_value(<<"topic">>, Params),
    emqx_mgmt:unsubscribe(ClientId, Topic).

topics(Params) ->
    Topics = [get_value(<<"topic">>, Params, <<"">>) | binary:split(get_value(<<"topics">>, Params, <<"">>), <<",">>, [global])],
    [Topic || Topic <- Topics, Topic =/= <<"">>].

%%TODO:

%%validate(qos, Qos) ->
%%    (Qos >= ?QOS_0) and (Qos =< ?QOS_2);

%%validate(topic, Topic) ->
%%    emqx_topic:validate({name, Topic}).

%% Internal function
check_required_params(Params) ->
    check_required_params(Params, required_params()).

check_required_params(_, []) -> ok;
check_required_params(Params, [Key | Rest]) ->
    case lists:keytake(Key, 1, Params) of
        {value, _, NewParams} -> check_required_params(NewParams, Rest);
        false                 -> {error, binary_to_list(Key) ++ " must be specified"}
    end.

required_params() ->
  [
    <<"task_id">>,
    <<"callback">>,
    <<"topic">>,
    <<"payload">>
  ].

mountpoint(Params) ->
    Topic     = get_value(<<"topic">>, Params),
    Protocol  = get_value(<<"protocol">>, Params),
    TenantID  = get_value(<<"tenantID">>, Params),
    ProductID = get_value(<<"productID">>, Params),
    GroupIDOrDeviceID = case get_value(<<"groupID">>, Params) of
        undefined -> get_value(<<"deviceID">>, Params);
        GroupID -> GroupID
    end,
    emqx_topic:encode(Topic, [<<"dn">>, Protocol, TenantID, ProductID, GroupIDOrDeviceID]).
