%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_api_banned).

-include_lib("emqx/include/emqx.hrl").

-import(proplists, [get_value/2, get_value/3]).

-rest_api(#{name   => list_banned,
            method => 'GET',
            path   => "/banned/",
            func   => list,
            descr  => "List banned"}).

-rest_api(#{name   => create_banned,
            method => 'POST',
            path   => "/banned/",
            func   => create,
            descr  => "Create banned"}).

-rest_api(#{name   => delete_banned,
            method => 'DELETE',
            path   => "/banned/:id",
            func   => delete,
            descr  => "Delete banned"}).

-export([list/2, create/2, delete/2]).

list(_Bindings, Params) ->
    {ok, emqx_mgmt_api:paginate(emqx_banned, Params, fun format_list/1)}.

create(_Bindings, Banned) ->
    Who = get_value(<<"who">>, Banned, <<>>),
    Reason = get_value(<<"reason">>, Banned, <<>>),
    By = get_value(<<"by">>, Banned, <<>>),
    Desc = get_value(<<"desc">>, Banned, <<>>),
    Util = get_value(<<"until">>, Banned, <<>>),
    BasicBanned = #emqx_banned{reason = Reason,
                          by = By,
                          desc = Desc,
                          until = Util},
    Result = lists:foldl(fun(WhoT, Acc) ->
                 case get_value(WhoT, Who, nil) of
                     nil -> Acc;
                     WhoV ->
                         [emqx_mgmt:create_banned(
                             BasicBanned#emqx_banned{who = {WhoT, WhoV}}) | Acc]
                 end
             end, [], [<<"all">>, <<"client">>, <<"user">>, <<"ipaddr">>]),
    {ok, format_list(Result)}.

delete(#{id := BannedID}, _Params) ->
    emqx_mgmt:delete_banned(bin(BannedID)), ok.

format_list(BannedList) ->
    [format(Ban) || Ban <- BannedList].

format(#emqx_banned{who = {K, V}} = Banned) ->
    maps:from_list(banned_to_proplist(Banned#emqx_banned{who=#{K => V}})).

banned_to_proplist(#emqx_banned{} = Rec) ->
  lists:zip(record_info(fields, emqx_banned), tl(tuple_to_list(Rec))).

bin(L) when is_list(L) ->
    list_to_binary(L);
bin(B) when is_binary(B) ->
    B.
