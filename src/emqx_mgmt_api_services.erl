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

-module(emqx_mgmt_api_services).

-include_lib("emqx/include/emqx.hrl").

-rest_api(#{name   => list_services,
            method => 'GET',
            path   => "/services/",
            func   => list,
            descr  => "List services"}).

-rest_api(#{name   => lookup_services,
            method => 'GET',
            path   => "/services/:atom:name",
            func   => lookup,
            descr  => "Lookup services by a name"}).

-rest_api(#{name   => list_instances,
            method => 'GET',
            path   => "/instances",
            func   => list_instances,
            descr  => "List instances"}).

-rest_api(#{name   => lookup_instances,
            method => 'GET',
            path   => "/instances/:bin:id",
            func   => lookup_instances,
            descr  => "Look up instances"}).

-rest_api(#{name   => create_instances,
            method => 'POST',
            path   => "/instances",
            func   => create_instances,
            descr  => "Create instance"}).

-rest_api(#{name   => delete_instances,
            method => 'DELETE',
            path   => "/instances",
            func   => delete_instances,
            descr  => "Delete instance"}).

%% REST API
-export([list/2, lookup/2]).
-export([list_instances/2, lookup_instances/2, create_instances/2, delete_instances/2]).

list(Bindings, Params) when map_size(Bindings) =:= 0 ->
    %% TODO: support type, status, name query???
    {ok, emqx_mgmt_api:paginate(mqtt_service, Params, fun fm_overview/1)}.

lookup(#{name := Name}, _Params) ->
    {ok, fm_allinfo(emqx_services:lookup(Name))}.

%%--------------------------------------------------------------------
%% Instances API
%%--------------------------------------------------------------------
list_instances(_Bindings, Params) ->
    %% TODO: support type, status, name query???
    {ok, emqx_mgmt_api:paginate(mqtt_instance, Params, fun fm_overview/1)}.

lookup_instances(#{id := Id}, _Parasm) ->
    {ok, fm_allinfo(emqx_services:lookup_instance(Id))}.

create_instances(_Bindings, Params) ->
    Name = proplists:get_value(<<"name">>, Params),
    Descr = proplists:get_value(<<"descr">>, Params),
    Service = b2a(proplists:get_value(<<"serviceName">>, Params)),
    Config = proplists:get_value(<<"config">>, Params),
    emqx_services:create_instance(Service, Name, Descr, config(Config)).

delete_instances(Binding, Params) ->
    InstanceId = proplists:get_value(<<"instanceId">>, Params),
    emqx_services:destroy_instance(InstanceId).

%%--------------------------------------------------------------------
%% Interval Funs
%%--------------------------------------------------------------------

fm_overview(Entriy) -> format(Entriy, false).

fm_allinfo(Entriy) -> format(Entriy, true).

format(#mqtt_service{name=Name, type=Type, status=Status, descr=Descr, nodes=Nodes, schema=Schema}, DisplaySchema) ->
    Res = #{name => Name, type => Type, status => Status, descr => Descr, nodes => Nodes, instances => instance_status(Name)},
    case DisplaySchema of
        false -> Res;
        true  -> Res#{schema => tune(Schema)}
    end;

format(#mqtt_instance{id=Id, name=Name, service=Service, descr=Descr, status=Status, nodes=Nodes, conf=Conf}, DisplayConf) ->
    Res = #{id => Id, name => Name, service => Service, descr => Descr, status => Status, nodes => Nodes},
    case DisplayConf of
        false -> Res;
        true  ->
            Conf1 = lists:map(fun to_bin/1, Conf),
            Res#{conf => Conf1}
    end.

instance_status(Service) ->
    #{running => 10, stopping => 1}.

tune(Schema) -> tune(Schema, []).

tune([], Acc) -> lists:reverse(Acc);
tune([H|T], Acc) ->
    Deft1 = lists:map(fun to_bin/1, proplists:get_value(default, H)),
    Deft2 = case Deft1 of
                [V] -> V;
                _   -> Deft1
            end,
    tune(T, [set_value(default, Deft2, H) | Acc]).

config(Conf) -> config(Conf, []).

config([], Acc) -> lists:reverse(Acc);
config([{Key, Value}|T], Acc) ->
    config(T, [{binary_to_existing_atom(Key, utf8), Value}|Acc]).

set_value(Key, Value, PL) ->
    [{Key, Value} | proplists:delete(Key, PL)].

to_bin({K, V}) when is_list(V) -> {K, list_to_binary(V)};
to_bin(V) when is_list(V) -> list_to_binary(V);
to_bin(V) -> V.


b2a(B) when is_binary(B) -> binary_to_existing_atom(B, utf8).

