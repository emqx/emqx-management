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

-module(emqx_mgmt_api_listeners).

-export([ get/3
        , list_listeners/2]).

-define(ALLOWED_METHODS, [<<"GET">>]).

-http_api(#{resource => "/listeners",
            allowed_methods => ?ALLOWED_METHODS,
            get => #{func => get,
                     qs => [{<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}]}}).

get(#{<<"node">> := Node}, _, _) ->
    case lists:member(Node, ekka_mnesia:cluster_nodes(all)) of
        false ->
            {200, []};
        true ->
            {200, list_listeners(Node)}
    end;
get(_, _, _) ->
    {200, list_listeners(ekka_mnesia:running_nodes())}.

list_listeners(Node) when is_atom(Node) ->
    list_listeners([Node]);
list_listeners(Nodes) when is_list(Nodes) ->
    list_listeners(Nodes, []).

list_listeners([], Acc) ->
    Acc;
list_listeners([Node | More], Acc) when Node =:= node() ->
    TCPListeners = lists:map(fun({{Protocol, ListenOn}, Pid}) ->
                                 #{name           => Protocol,
                                   listen_on      => list_to_binary(esockd:to_string(ListenOn)),
                                   acceptors      => esockd:get_acceptors(Pid),
                                   max_conns      => esockd:get_max_connections(Pid),
                                   current_conns  => esockd:get_current_connections(Pid),
                                   shutdown_count => maps:from_list(esockd:get_shutdown_count(Pid))}
                    end, esockd:listeners()),
    HTTPListeners = lists:map(fun({Protocol, Opts}) ->
                              #{name           => Protocol,
                                listen_on      => list_to_binary(esockd:to_string(proplists:get_value(port, Opts))),
                                acceptors      => maps:get(num_acceptors, proplists:get_value(transport_options, Opts)),
                                max_conns      => proplists:get_value(max_connections, Opts),
                                current_conns  => proplists:get_value(all_connections, Opts),
                                shutdown_count => #{}}
                       end, ranch:info()),
    list_listeners(More, [#{node => Node, listeners => TCPListeners ++ HTTPListeners} | Acc]);
list_listeners(Nodes = [Node | _], Acc) ->
    emqx_mgmt_api:remote_call(Node, list_listeners, [Nodes, Acc]).