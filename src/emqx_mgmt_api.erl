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

-module(emqx_mgmt_api).

-author("Feng Lee <feng@emqtt.io>").

-include_lib("stdlib/include/qlc.hrl").

-export([paginate/4]).

paginate(Qh, Count, Params, RowFun) ->
    Page = page(Params),
    Limit = limit(Params),
    Cursor = qlc:cursor(Qh),
    case Page > 1 of
        true  -> qlc:next_answers(Cursor, (Page - 1) * Limit);
        false -> ok
    end,
    Rows = qlc:next_answers(Cursor, Limit),
    qlc:delete_cursor(Cursor),
    #{meta  => #{page => Page, limit => Limit, count => Count},
      items => [RowFun(Row) || Row <- Rows]}.

page(Params) ->
    list_to_integer(proplists:get_value("page", Params, "1")).

limit(Params) ->
    case proplists:get_value("limit", Params) of
        undefined -> emqx_mgmt:max_row_limit();
        Size      -> list_to_integer(Size)
    end.

