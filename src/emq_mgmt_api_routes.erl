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

-module(emq_mgmt_api_routes).

-author("Feng Lee <feng@emqtt.io>").

-rest_api(#{name   => list_routes,
            method => 'GET',
            path   => "/routes/",
            func   => list,
            descr  => "List routes"}).

-rest_api(#{name   => lookup_routes,
            method => 'GET',
            url    => "/routes/:topic",
            func   => lookup,
            descr  => "Lookup routes to a topic"}}).

-export([list/2, lookup/2]).

list(Bindings, Params) when map_size(Bindings) == 0 ->
    {ok, emq_mgmt_api:paginate(emq_mgmt:query_handle(routes),
                               emq_mgmt:count(routes), Params,
                               fun(R) -> emq_mgmt:item(route, R) end)}.

lookup(#{topic := Topic}, _Params) ->
    {ok, #{items => emq_mgmt:lookup_routes(Topic)}}.

