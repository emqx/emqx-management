%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_api_metrics).

-import(minirest, [return/1]).

-rest_api(#{name   => list_all_metrics,
            method => 'GET',
            path   => "/metrics/",
            func   => list,
            descr  => "A list of metrics of all nodes in the cluster"}).

-rest_api(#{name   => list_all_topic_metrics,
            method => 'GET',
            path   => "/metrics/topic/:bin:topic",
            func   => list,
            descr  => "A list of topic metrics of all nodes in the cluster"}).

-rest_api(#{name   => list_node_metrics,
            method => 'GET',
            path   => "/nodes/:atom:node/metrics/",
            func   => list,
            descr  => "A list of metrics of a node"}).

-rest_api(#{name   => list_node_topic_metrics,
            method => 'GET',
            path   => "/nodes/:atom:node/metrics/topic/:bin:topic",
            func   => list,
            descr  => "A list of topic metrics of a node"}).

-rest_api(#{name   => add_topic_metrics,
            method => 'POST',
            path   => "/metrics/topic/:bin:topic",
            func   => add_metrics,
            descr  => "Add a series of metrics"}).

-rest_api(#{name   => del_topic_metrics,
            method => 'DELETE',
            path   => "/metrics/topic/:bin:topic",
            func   => del_metrics,
            descr  => "Delete a series of metrics"}).

-export([ list/2
        , add_metrics/2
        , del_metrics/2
        ]).

list(Bindings, _Params) when map_size(Bindings) == 0 ->
    return({ok, [[{node, Node}, {metrics, Metrics}]
                              || {Node, Metrics} <- emqx_mgmt:get_metrics()]});

list(#{node := Node, topic := Topic}, _Params) ->
    case emqx_mgmt:get_metrics(Node, topic_metrics, http_uri:decode(Topic)) of
        {error, Reason} -> return({error, Reason});
        Metrics         -> return({ok, Metrics})
    end;

list(#{topic := Topic}, _Params) ->
    return({ok, [[{node, Node}, {metrics, Metrics}]
                              || {Node, Metrics} <- emqx_mgmt:get_metrics(topic_metrics, http_uri:decode(Topic))]});

list(#{node := Node}, _Params) ->
    case emqx_mgmt:get_metrics(Node) of
        {error, Reason} -> return({error, Reason});
        Metrics         -> return({ok, Metrics})
    end.

add_metrics(#{topic := Topic}, _Params) ->
    return(emqx_mgmt:add_metrics(topic_metrics, http_uri:decode(Topic))).

del_metrics(#{topic := Topic}, _Params) ->
    return(emqx_mgmt:del_metrics(topic_metrics, http_uri:decode(Topic))).

