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

-module(emqx_mgmt_api_topic_metrics).

-import(minirest, [return/1]).

-rest_api(#{name   => list_all_topic_metrics,
            method => 'GET',
            path   => "/topic-metrics",
            func   => list,
            descr  => "A list of all topic metrics of all nodes in the cluster"}).

-rest_api(#{name   => list_topic_metrics,
            method => 'GET',
            path   => "/topic-metrics/:bin:topic",
            func   => list,
            descr  => "A list of specfied topic metrics of all nodes in the cluster"}).

-rest_api(#{name   => register_topic_metrics,
            method => 'POST',
            path   => "/topic-metrics/:bin:topic",
            func   => register,
            descr  => "Register topic metrics"}).

-rest_api(#{name   => unregister_all_topic_metrics,
            method => 'DELETE',
            path   => "/topic-metrics",
            func   => unregister,
            descr  => "Unregister all topic metrics"}).

-rest_api(#{name   => unregister_topic_metrics,
            method => 'DELETE',
            path   => "/topic-metrics/:bin:topic",
            func   => unregister,
            descr  => "Unregister topic metrics"}).

-export([ list/2
        , register/2
        , unregister/2
        ]).

list(#{topic := Topic0}, _Params) ->
    Topic = http_uri:decode(Topic0),
    case emqx_mgmt:get_topic_metrics(Topic) of
        {error, Reason} -> return({error, Reason});
        Metrics         -> return({ok, maps:from_list(Metrics)})
    end;
list(_Bindings, _Params) ->
    case emqx_mgmt:get_all_topic_metrics() of
        {error, Reason} -> return({error, Reason});
        Metrics         -> return({ok, maps:from_list(Metrics)})
    end.

register(#{topic := Topic0}, _Params) ->
    Topic = http_uri:decode(Topic0),
    emqx_mgmt:register_topic_metrics(Topic),
    return(ok).

unregister(Bindings, _Params) when map_size(Bindings) =:= 0 ->
    emqx_mgmt:unregister_all_topic_metrics(),
    return(ok);

unregister(#{topic := Topic0}, _Params) ->
    Topic = http_uri:decode(Topic0),
    emqx_mgmt:unregister_topic_metrics(Topic),
    return(ok).


