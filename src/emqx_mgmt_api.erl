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

-module(emqx_mgmt_api).

-include_lib("stdlib/include/qlc.hrl").

-export([ remote_call/3
        , validate_node/1
        , validate_topic_filter/1
        , validate_topic_name/1
        , paginate/3]).

remote_call(Node, Fun, Args) ->
    case rpc:call(Node, ?MODULE, Fun, Args) of
        {badrpc, Reason} -> error({badrpc, Reason});
        Result -> Result
    end.

validate_node(Node) when is_binary(Node) ->
    case binary:split(Node, <<$@>>, [global, trim]) of
        [_, _] -> {ok, binary_to_atom(Node, utf8)};
        _ -> {error, not_valid_node}
    end.

validate_topic_filter(Topic) when is_binary(Topic) ->
    try emqx_topic:validate(filter, Topic) of
        true -> {ok, Topic}
    catch
        error:_ ->
            {error, not_valid_topic_filter}
    end.

validate_topic_name(Topic) when is_binary(Topic) ->
    try emqx_topic:validate(name, Topic) of
        true -> {ok, Topic}
    catch
        error:_ ->
            {error, not_valid_topic_name}
    end.

paginate(Tables, #{<<"page">> := Page,
                   <<"limit">> := Limit}, RowFun) ->
    Qh = query_handle(Tables),
    Count = count(Tables),
    Cursor = qlc:cursor(Qh),
    case Page > 1 of
        true  -> qlc:next_answers(Cursor, (Page - 1) * Limit);
        false -> ok
    end,
    Rows = qlc:next_answers(Cursor, Limit),
    qlc:delete_cursor(Cursor),
    #{meta  => #{page => Page, limit => Limit, count => Count},
      data  => [RowFun(Row) || Row <- Rows]}.

query_handle(Table) when is_atom(Table) ->
    qlc:q([R|| R <- ets:table(Table)]);
query_handle([Table]) when is_atom(Table) ->
    qlc:q([R|| R <- ets:table(Table)]);
query_handle(Tables) ->
    qlc:append([qlc:q([E || E <- ets:table(T)]) || T <- Tables]).

count(Table) when is_atom(Table) ->
    ets:info(Table, size);
count([Table]) when is_atom(Table) ->
    ets:info(Table, size);
count(Tables) ->
    lists:sum([count(T) || T <- Tables]).
