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

-module(emq_mgmt_api).

-author("Feng Lee <feng@emqtt.io>").

-export([paginate/4]).

paginate(Qh, Count, Params, RowFun) ->
    Page = page_no(Params),
    Size = page_size(Params),
    Cursor = qlc:cursor(Qh),
    case Page > 1 of
        true  -> qlc:next_answers(Cursor, (Page - 1) * Size);
        false -> ok
    end,
    Rows = qlc:next_answers(Cursor, Size),
    qlc:delete_cursor(Cursor),
    #{page        => Page,
      page_size   => Size,
      total_pages => total_pages(Count, Size),
      total_count => Count,
      items       => [RowFun(Row) || Row <- Rows]}.

total_pages(TotalCount, PageSize) ->
    case TotalCount rem PageSize of
        0 -> TotalCount div PageSize;
        _ -> (TotalCount div PageSize) + 1
    end.

page_no(Params) ->
    list_to_integer(proplists:get_value("page", Params, "1")).

page_size(Params) ->
    case proplists:get_value("size", Params) of
        undefined -> emq_mgmt:max_row_limit();
        Size      -> list_to_integer(Size)
    end.

