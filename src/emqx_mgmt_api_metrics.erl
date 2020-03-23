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

-module(emqx_mgmt_api_metrics).

-export([ get/3
        , get_metrics/2]).

-define(ALLOWED_METHODS, [<<"GET">>]).

-http_api(#{resource => "/metrics",
            allowed_methods => ?ALLOWED_METHODS,
            get => #{func => get,
                     qs => [{<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}]}}).

get(#{<<"node">> := Node}, _, _) ->
    case lists:member(Node, ekka_mnesia:cluster_nodes(all)) of
        false ->
            Message = minirest_req:serialize("The node '~s' is not in the current cluster", [Node]),
            {400, #{message => Message}};
        true ->
            {200, get_metrics(Node)}
    end;
get(_, _, _) ->
    {200, get_metrics(ekka_mnesia:running_nodes())}.

get_metrics(Node) when is_atom(Node) ->
    get_metrics([Node]);
get_metrics(Nodes) when is_list(Nodes) ->
    get_metrics(Nodes, []).

get_metrics([], Acc) ->
    Acc;
get_metrics([Node | More], Acc) when Node =:= node() ->
    get_metrics(More, [#{node => Node, metrics => maps:from_list(emqx_metrics:all())} | Acc]);
get_metrics(Nodes = [Node | _], Acc) ->
    emqx_mgmt_api:remote_call(Node, get_metrics, [Nodes, Acc]).