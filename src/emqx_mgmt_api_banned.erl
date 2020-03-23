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

-module(emqx_mgmt_api_banned).

-include_lib("emqx/include/emqx.hrl").

-export([ get/3
        , post/3
        , put/3
        , delete/3
        , validate_peerhost/1]).

-define(ALLOWED_METHODS, [<<"GET">>, <<"POST">>, <<"PUT">>, <<"DELETE">>]).

-define(DEFAULT_REASON, <<"Unknown">>).
-define(DEFAULT_DURATION, 300).

-http_api(#{resource => "/banned",
            allowed_methods => ?ALLOWED_METHODS,
            get => #{qs => [{[<<"clientid">>, <<"username">>, <<"peerhost">>], [at_most_one]},
                            {<<"clientid">>, optional, [nonempty]},
                            {<<"username">>, optional, [nonempty]},
                            {<<"peerhost">>, optional, [fun ?MODULE:validate_peerhost/1]},
                            {<<"page">>, {optional, 1}, [int]},
                            {<<"limit">>, {optional, 20}, [int]},
                            {<<"human-readable">>, {optional, true}, [bool]}]},
            post => #{body => [{[<<"clientid">>, <<"username">>, <<"peerhost">>], [exactly_one]},
                               {<<"clientid">>, optional, [nonempty]},
                               {<<"username">>, optional, [nonempty]},
                               {<<"peerhost">>, optional, [fun ?MODULE:validate_peerhost/1]},
                               {<<"reason">>, {optional, ?DEFAULT_REASON}, [nonempty]},
                               {<<"duration">>, {optional, ?DEFAULT_DURATION}, [int]}]},
            put => #{qs => [{[<<"clientid">>, <<"username">>, <<"peerhost">>], [exactly_one]},
                              {<<"clientid">>, optional, [nonempty]},
                              {<<"username">>, optional, [nonempty]},
                              {<<"peerhost">>, optional, [fun ?MODULE:validate_peerhost/1]}],
                     body => [{[<<"reason">>, <<"duration">>], [at_least_one]},
                              {<<"reason">>, optional, [nonempty]},
                              {<<"duration">>, optional, [int]}]},
            delete => #{qs => [{[<<"clientid">>, <<"username">>, <<"peerhost">>], [exactly_one]},
                               {<<"clientid">>, optional, [nonempty]},
                               {<<"username">>, optional, [nonempty]},
                               {<<"peerhost">>, optional, [fun ?MODULE:validate_peerhost/1]}]}}).

get(Params, _, _) ->
    try parse_who(Params) of
        Who ->
            case emqx_banned:lookup(Who) of
                none -> {404, #{message => <<"No ban record was found">>}};
                Row -> {200, format(Row, Params)}
            end
    catch
        error:_ ->
            Fun = fun(Row) ->
                      format(Row, Params)
                  end,
            {200, emqx_mgmt_api:paginate(emqx_banned, Params, Fun)}
    end.

post(_, _, Body = #{<<"reason">> := Reason,
                    <<"duration">> := Duration}) ->
    Who = parse_who(Body),
    case emqx_banned:lookup(Who) of
        none ->
            Now = erlang:system_time(second),
            Banned = #banned{who = Who,
                            by = <<"HTTP API">>,
                            reason = Reason,
                            at = Now,
                            until = Now + Duration},
            ok = emqx_banned:create(Banned),
            201;
        _ ->
            {409, #{message => <<"The corresponding resource already exists">>}}
    end.

put(Params, _, Body) ->
    Who = parse_who(Params),
    case emqx_banned:lookup(Who) of
        none ->
            Now = erlang:system_time(second),
            Banned = #banned{who = Who,
                            by = <<"HTTP API">>,
                            reason = maps:get(<<"reason">>, Body, ?DEFAULT_REASON),
                            at = Now,
                            until = Now + maps:get(<<"duration">>, Body, ?DEFAULT_DURATION)},
            ok = emqx_banned:create(Banned),
            201;
        Banned ->
            NBanned = update_fields(Banned, maps:to_list(maps:with([<<"reason">>, <<"duration">>], Body))),
            emqx_banned:create(NBanned),
            204
    end.

update_fields(Banned, []) ->
    Banned;
update_fields(Banned = #banned{}, [{<<"reason">>, Reason} | More]) ->
    update_fields(Banned#banned{reason = Reason}, More);
update_fields(Banned = #banned{}, [{<<"duration">>, Duration} | More]) ->
    update_fields(Banned#banned{until = Banned#banned.at + Duration}, More);
update_fields(Banned = #banned{}, [_ | More]) ->
    update_fields(Banned, More).

delete(Params, _, _) ->
    Who = parse_who(Params),
    ok = emqx_banned:delete(Who),
    204.

validate_peerhost(Peerhost) ->
    inet:parse_address(binary_to_list(Peerhost)).

parse_who(#{<<"clientid">> := ClientId}) ->
    {clientid, ClientId};
parse_who(#{<<"username">> := Username}) ->
    {username, Username};
parse_who(#{<<"peerhost">> := PeerHost}) ->
    {peerhost, PeerHost}.

format(#banned{who = Who, by = By, reason = Reason, at = At, until = Until}, #{<<"human-readable">> := HumanReadable}) ->
    Formatted = case Who of
                    {clientid, ClientId} ->
                        #{<<"clientid">> => ClientId};
                    {username, Username} ->
                        #{<<"username">> => Username};
                    {peerhost, PeerHost} ->
                        #{<<"peerhost">> => PeerHost}
                end,
    Formatted#{by => By,
               reason => Reason,
               at => case HumanReadable of
                         true -> human_readable_timestamp(At);
                         false -> At
                     end,
               until => case HumanReadable of
                            true -> human_readable_timestamp(Until);
                            false -> At
                        end}.

human_readable_timestamp(Timestamp) when is_integer(Timestamp) ->
    list_to_binary(emqx_mgmt_util:strftime(Timestamp)).