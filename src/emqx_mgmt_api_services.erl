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
            path   => "/instances/:bin:id",
            func   => delete_instances,
            descr  => "Delete instance"}).

-rest_api(#{name   => update_instances,
            method => 'PUT',
            path   => "/instances/:bin:id",
            func   => update_instances,
            descr  => "Update instance"}).

-rest_api(#{name   => start_instances,
            method => 'PUT',
            path   => "/instances/:bin:id/start",
            func   => start_instance,
            descr  => "Start instance"}).

-rest_api(#{name   => stop_instances,
            method => 'PUT',
            path   => "/instances/:bin:id/stop",
            func   => stop_instance,
            descr  => "Stop instance"}).


%% REST API
-export([list/2, lookup/2]).
-export([list_instances/2, lookup_instances/2, create_instances/2,
         delete_instances/2, update_instances/2, start_instance/2,
         stop_instance/2]).

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
    Name = value(<<"name">>, Params),
    Descr = value(<<"descr">>, Params),
    Service = b2a(value(<<"serviceName">>, Params)),
    Config = value(<<"config">>, Params),
    emqx_services:create_instance(Service, Name, Descr, Config).

delete_instances(#{id := Id}, _Params) ->
    emqx_services:destroy_instance(Id).

update_instances(#{id := Id}, Params) ->
    %% FIXME: need update Name & Descr
    Config = value(<<"config">>, Params),
    Name = value(<<"name">>, Params),
    Descr = value(<<"descr">>, Params),
    emqx_services:update_instance(Id, Name, Descr, Config).

start_instance(#{id := Id}, _Params) ->
    emqx_services:enable_instance(Id, 1).

stop_instance(#{id := Id}, _Params) ->
    emqx_services:enable_instance(Id, 0).

%%--------------------------------------------------------------------
%% Interval Funs
%%--------------------------------------------------------------------

fm_overview(Entriy) -> format(Entriy, false).

fm_allinfo(Entriy) -> format(Entriy, true).

format(#mqtt_service{name=App, type=Type, status=Status, descr=Descr, nodes=Nodes}, DisplaySchema) ->
    Res = #{name => App, type => Type, status => Status, descr => Descr, nodes => Nodes, instances => instance_status(App)},
    case DisplaySchema of
        false -> Res;
        true  ->
            {ok, Schema} = emqx_services:fetch_schema(App),
            Res#{schema => tune(Schema)}
    end;

format(#mqtt_instance{id=Id, name=Name, service=Service, descr=Descr,
                      status=Status, nodes=Nodes, conf=Conf, create_at=CreateAt}, DisplayConf) ->
    Res = #{id => Id, name => Name, service => Service, descr => Descr,
            status => Status, nodes => Nodes, type => type(Service), createAt => CreateAt},
    case DisplayConf of
        false -> Res;
        true  ->
            Conf1 = lists:map(fun to_bin/1, Conf),
            Res#{conf => Conf1}
    end.

instance_status(Name) ->
    #{running => emqx_services:running(Name),
      stopped => emqx_services:stopped(Name)}.

type(Name) ->
    [#mqtt_service{type=Type}] = mnesia:dirty_read(mqtt_service, Name), Type.

tune(Schema) -> tune(Schema, []).

tune([], Acc) -> lists:reverse(Acc);
tune([H = #{key := Key, default := Deft, descr := Descr}|T], Acc) ->
    Deft1 = lists:map(fun to_bin/1, Deft),
    Deft2 = case Deft1 of
                []  -> <<"">>;
                [V] -> V;
                _   -> Deft1
            end,
    tune(T, [H#{key := to_bin(Key), descr := to_bin(Descr), default := Deft2} | Acc]).

value(Key, PL) -> proplists:get_value(Key, PL).

to_bin({K, V}) when is_list(V) -> {K, list_to_binary(V)};
to_bin(V) when is_list(V) -> list_to_binary(V);
to_bin(V) -> V.


b2a(B) when is_binary(B) -> binary_to_existing_atom(B, utf8).

