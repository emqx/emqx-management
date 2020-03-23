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

-module(emqx_mgmt_api_status).

-export([get/3]).

-export([list_status/2]).

-import(proplists, [get_value/2]).

-http_api(#{resource => "/status",
            allowed_methods => [<<"GET">>],
            get => #{qs => [{<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}]}}).


get(#{<<"node">> := Node}, _, _) ->
    case lists:member(Node, ekka_mnesia:cluster_nodes(all)) of
        false ->
            {200, []};
        true ->
            {200, list_status(Node)}
    end;
get(_, _, _) ->
    {200, list_status(ekka_mnesia:running_nodes())}.

list_status(Node) when is_atom(Node) ->
    list_status([Node]);
list_status(Nodes) when is_list(Nodes) ->
    list_status(Nodes, []).
    
list_status([], Acc) ->
    Acc;
list_status([Node | More], Acc) when Node =:= node() ->
    list_status(More, [#{node => Node, status => status()} | Acc]);
list_status(Nodes = [Node | _], Acc) ->
    emqx_mgmt_api:remote_call(Node, list_status, [Nodes, Acc]).

status() ->
    Memory = emqx_vm:get_memory(),
    Loads = emqx_vm:loads(),
    BrokerInfo = emqx_sys:info(),
    #{name              => node(),
      version           => iolist_to_binary(get_value(version, BrokerInfo)),
      sysdescr          => iolist_to_binary(get_value(sysdescr, BrokerInfo)),
      otp_release       => otp_release(),
      uptime            => iolist_to_binary(get_value(uptime, BrokerInfo)),
      datetime          => iolist_to_binary(get_value(datetime, BrokerInfo)),
      load1             => iolist_to_binary(get_value(load1, Loads)),
      load5             => iolist_to_binary(get_value(load5, Loads)),
      load15            => iolist_to_binary(get_value(load15, Loads)),
      memory_total      => emqx_mgmt_util:kmg(get_value(allocated, Memory)),
      memory_used       => emqx_mgmt_util:kmg(get_value(used, Memory)),
      process_available => erlang:system_info(process_limit),
      process_used      => erlang:system_info(process_count),
      max_fds           => get_value(max_fds, lists:usort(lists:flatten(erlang:system_info(check_io)))),
      connections       => ets:info(emqx_conn, size)}.

% normalize_fields(Fields) ->
%     normalize_fields(Fields, []).

% normalize_fields([], Acc) ->
%     Acc;
% normalize_fields([{} | More], Acc) ->


otp_release() ->
    iolist_to_binary(lists:concat(["R", erlang:system_info(otp_release), "/", erlang:system_info(version)])).

% /api/v4/brokers
%     "otp_release": "R21/10.3.2",
%     "sysdescr": "EMQ X Broker",
%     "uptime": "7 minutes, 16 seconds",
%     "version": "v3.1.0"

% /api/v4/system
% /api/v4/nodes
%       "connections": 2,
%       "load1": "2.75",
%       "load15": "2.87",
%       "load5": "2.57",
%       "max_fds": 7168,
%       "memory_total": "76.45M",
%       "memory_used": "59.48M",
%       "name": "emqx@127.0.0.1",
%       "node": "emqx@127.0.0.1",
%       "node_status": "Running",
%       "otp_release": "R21/10.3.2",
%       "process_available": 262144,
%       "process_used": 331,
%       "uptime": "1 days,18 hours, 45 minutes, 1 seconds",
%       "version": "v3.1.0"