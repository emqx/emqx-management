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

-module(emqx_mgmt_api_stats).

-export([ get/3
        , get_stats/2]).

-define(ALLOWED_METHODS, [<<"GET">>]).

-http_api(#{resource => "/stats",
            allowed_methods => ?ALLOWED_METHODS,
            get => #{qs => [{<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}]}}).

get(#{<<"node">> := Node}, _, _) ->
    case lists:member(Node, ekka_mnesia:cluster_nodes(all)) of
        false ->
            Message = minirest_req:serialize("The node '~s' is not in the current cluster", [Node]),
            {400, #{message => Message}};
        true ->
            {200, get_stats(Node)}
    end;
get(_, _, _) ->
    {200, get_stats(ekka_mnesia:running_nodes())}.

get_stats(Node) when is_atom(Node) ->
    get_stats([Node]);
get_stats(Nodes) when is_list(Nodes) ->
    get_stats(Nodes, []).

get_stats([], Acc) ->
    Acc;
get_stats([Node | More], Acc) when Node =:= node() ->
    get_stats(More, [#{node => Node, stats => maps:from_list(emqx_stats:getstats())} | Acc]);
get_stats(Nodes = [Node | _], Acc) ->
    emqx_mgmt_api:remote_call(Node, get_stats, [Nodes, Acc]).