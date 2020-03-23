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

-module(emqx_mgmt_api_clients).

-export([ get/3
        , delete/3
        ]).

-import(emqx_mgmt_util, [ ntoa/1
                        , strftime/1
                        ]).

-http_api(#{resource => "/clients",
            allowed_methods => [<<"GET">>],
            get => #{qs => [{<<"username">>, optional, [nonempty]},
                            {<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}]}}).

-http_api(#{resource => "/clients/:clientid",
            allowed_methods => [<<"GET">>, <<"DELETE">>]}).

get(#{<<"clientid">> := ClientId}, _, _) ->
    case lookup_client(ClientId) of
        {error, not_found} ->
            {404, #{message => <<"The specified client was not found">>}};
        Client ->
            {200, Client}
    end;
get(#{<<"username">> := Username, <<"node">> := Node}, _, _) ->
    200;
get(#{<<"username">> := Username}, _, _) ->
    200;
get(#{<<"node">> := Node}, _, _) ->
    200.

delete(#{<<"clientid">> := ClientId}, _, _) ->
    case emqx_cm:kick_session(ClientId) of
        {error, not_found} ->
            {404, #{message => <<"The specified client was not found">>}};
        ok ->
            204
    end.

lookup_client(ClientId) ->
    case emqx_cm:lookup_channels(ClientId) of
        [] -> {error, not_found};
        Pids ->
            lookup_client(ClientId, lists:last(Pids))
    end.

lookup_client(ClientId, ChanPid) when node(ChanPid) =:= node() ->
    case ets:lookup(emqx_channel_info, {ClientId, ChanPid}) of
        [] -> {error, not_found};
        [ChanInfo] -> format(ChanInfo)
    end;
lookup_client(ClientId, ChanPid) ->
    emqx_mgmt_api:remote_call(node(ChanPid), lookup_client, [ClientId, ChanPid]).

% list_clients(Username) ->
%     list_clients(ekka_mnesia:running_nodes(), Username).

% list_clients(Nodes, Username) ->
%     list_clients(Nodes, Username, []).

% %% TODO: Support paginate
% list_clients([], Username, Acc) ->
%     Acc;
% list_clients([Node | More], Username, Acc) when Node =:= node() ->
%     Acc;
% list_clients(Nodes = [Node | _], Username, Acc) ->
%     emqx_mgmt_api:remote_call(Nodes, list_clients, [Nodes, Username, Acc]).


format({_, Attrs, Stats}) ->
    ClientInfo = maps:get(clientinfo, Attrs, #{}),
    ConnInfo = maps:get(conninfo, Attrs, #{}),
    Session = maps:get(session, Attrs, #{}),
    ConnState = maps:with([conn_state], Attrs),
    Fields = maps:to_list(ClientInfo) ++ maps:to_list(ConnInfo) ++ maps:to_list(Session)
            ++ maps:to_list(ConnState) ++ [{node, node()}] ++ Stats,
    maps:from_list(normalize_fields(Fields)).

normalize_fields(Fields) ->
    normalize_fields(Fields, []).

normalize_fields([], Acc) ->
    Acc;
normalize_fields([{subscriptions_cnt, V} | More], Acc) ->
    normalize_fields(More, [{subscriptions, V} | Acc]);
normalize_fields([{subscriptions_max, V} | More], Acc) ->
    normalize_fields(More, [{max_subscriptions, V} | Acc]);
normalize_fields([{inflight_cnt, V} | More], Acc) ->
    normalize_fields(More, [{inflight, V} | Acc]);
normalize_fields([{inflight_max, V} | More], Acc) ->
    normalize_fields(More, [{max_inflight, V} | Acc]);
normalize_fields([{awaiting_rel_cnt, V} | More], Acc) ->
    normalize_fields(More, [{awaiting_rel, V} | Acc]);
normalize_fields([{awaiting_rel_max, V} | More], Acc) ->
    normalize_fields(More, [{max_awaiting_rel, V} | Acc]);
normalize_fields([{mqueue_max, V} | More], Acc) ->
    normalize_fields(More, [{max_mqueue, V} | Acc]);
normalize_fields([{conn_state, connected} | More], Acc) ->
    normalize_fields(More, [{connected, true} | Acc]);
normalize_fields([{conn_state, _} | More], Acc) ->
    normalize_fields(More, [{connected, false} | Acc]);
normalize_fields([{connected_at, ConnectedAt} | More], Acc) ->
    normalize_fields(More, [{connected_at, iolist_to_binary(strftime(ConnectedAt))} | Acc]);
normalize_fields([{disconnected_at, DisconnectedAt} | More], Acc) ->
    normalize_fields(More, [{disconnected_at, iolist_to_binary(strftime(DisconnectedAt))} | Acc]);
normalize_fields([{created_at, CreatedAt} | More], Acc) ->
    normalize_fields(More, [{created_at, iolist_to_binary(strftime(CreatedAt))} | Acc]);
normalize_fields([{peername, {IP, Port}} | More], Acc) ->
    normalize_fields(More, [{ip_address, iolist_to_binary(ntoa(IP))}, {port, Port} | Acc]);
normalize_fields([{K, V} | More], Acc) ->
    case lists:member(K, [clientid, username, proto_name, proto_ver, clean_start, keepalive, expiry_interval,
                          node, is_bridge, zone, mqueue_len, mqueue_dropped,
                          recv_cnt, recv_msg, recv_oct, recv_pkt,
                          send_cnt, send_msg, send_oct, send_pkt]) of
        true ->
            normalize_fields(More, [{K, V} | Acc]);
        false ->
            normalize_fields(More, Acc)
    end.

