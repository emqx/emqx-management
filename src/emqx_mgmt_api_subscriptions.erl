%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_api_subscriptions).

-export([ get/3
        , post/3
        , delete/3
        ]).

-export([ validate_qos/1
        , validate_nl/1
        , validate_rap/1
        , validate_rh/1
        ]).

-export([ do_subscribe/3
        , do_unsubscribe/3
        ]).

-http_api(#{resource => "/subscriptions",
            allowed_methods => [<<"GET">>, <<"POST">>, <<"DELETE">>],
            get => #{qs => [{[<<"clientid">>, <<"node">>], [at_most_one]},
                            {<<"clientid">>, optional, [nonempty]},
                            {<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}]},
            post => #{body => [{<<"clientid">>, [nonempty]},
                               {<<"topic">>, [fun emqx_mgmt_api:validate_topic_filter/1]},
                               {<<"qos">>, {optional, 0}, [int, fun ?MODULE:validate_qos/1]},
                               {<<"nl">>, {optional, 0}, [int, fun ?MODULE:validate_nl/1]},
                               {<<"rap">>, {optional, 0}, [int, fun ?MODULE:validate_rap/1]},
                               {<<"rh">>, {optional, 0}, [int, fun ?MODULE:validate_rh/1]}]},
            delete => #{qs => [{<<"clientid">>, [nonempty]},
                               {<<"topic">>, [fun emqx_mgmt_api:validate_topic_filter/1]}]}}).

get(_, _, _) ->
    200.

post(_, _, Body) ->
    case subscribe(Body) of
        [] ->
            201;
        Details ->
            {400, #{message => <<"Failed to complete all operations">>,
                    details => Details}}
    end.  

delete(Params, _, _) ->
    case unsubscribe(Params) of
        [] ->
            204;
        Details ->
            {400, #{message => <<"Failed to complete all operations">>,
                    details => Details}}
    end.  

subscribe(RawData) when is_map(RawData) ->
    subscribe([RawData], []).

subscribe([], Acc) ->
    Acc;
subscribe([#{<<"clientid">> := ClientId,
             <<"topic">> := Topic,
             <<"qos">> := QoS,
             <<"nl">> := NoLocal,
             <<"rap">> := RetainAsPublished,
             <<"rh">> := RetainHandling} = Data | More], Acc) ->
    case do_subscribe(ClientId, {Topic, #{qos => QoS,
                                          nl => NoLocal,
                                          rap => RetainAsPublished,
                                          rh => RetainHandling}}) of
        {error, not_found} ->
            NAcc = [#{data => Data,
                      error => <<"The specified client was not found">>} | Acc],
            subscribe(More, NAcc);
        ok ->
            subscribe(More, Acc)
    end.

do_subscribe(ClientId, Subscriptions) ->
    case emqx_cm:lookup_channels(ClientId) of
        [] -> {error, not_found};
        Pids ->
            do_subscribe(ClientId, lists:last(Pids), Subscriptions)
    end.

do_subscribe(_ClientId, ChanPid, Subscriptions) when node(ChanPid) =:= node() ->
    ChanPid ! {subscribe, Subscriptions};
do_subscribe(ClientId, ChanPid, Subscriptions) ->
    emqx_mgmt_api:remote_call(node(ChanPid), do_subscribe, [ClientId, ChanPid, Subscriptions]).

unsubscribe(RawData) when is_map(RawData) ->
    unsubscribe([RawData], []).

unsubscribe([], Acc) ->
    Acc;
unsubscribe([#{<<"clientid">> := ClientId,
               <<"topic">> := Topic} = Data | More], Acc) ->
    case do_unsubscribe(ClientId, Topic) of
        {error, not_found} ->
            NAcc = [#{data => Data,
                      error => <<"The specified client was not found">>} | Acc],
            unsubscribe(More, NAcc);
        ok ->
            unsubscribe(More, Acc)
    end.

do_unsubscribe(ClientId, Topic) ->
    case emqx_cm:lookup_channels(ClientId) of
        [] -> {error, not_found};
        Pids ->
            do_unsubscribe(ClientId, lists:last(Pids), Topic)
    end.

do_unsubscribe(_ClientId, ChanPid, Topic) when node(ChanPid) =:= node() ->
    ChanPid ! {unsubscribe, Topic};
do_unsubscribe(ClientId, ChanPid, Topic) ->
    emqx_mgmt_api:remote_call(node(ChanPid), do_unsubscribe, [ClientId, ChanPid, Topic]).

validate_qos(0) ->
    ok;
validate_qos(1) ->
    ok;
validate_qos(2) ->
    ok;
validate_qos(_) ->
    {error, not_valid_qos}.

validate_nl(0) ->
    ok;
validate_nl(1) ->
    ok;
validate_nl(_) ->
    {error, not_valid_nl}.

validate_rap(0) ->
    ok;
validate_rap(1) ->
    ok;
validate_rap(_) ->
    {error, not_valid_rap}.

validate_rh(0) ->
    ok;
validate_rh(1) ->
    ok;
validate_rh(2) ->
    ok;
validate_rh(_) ->
    {error, not_valid_rh}.