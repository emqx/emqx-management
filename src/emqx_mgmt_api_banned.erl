%%--------------------------------------------------------------------
%% Copyright (c) 2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-include("emqx_mgmt.hrl").

-import(proplists, [get_value/2]).

-import(minirest, [ return/0
                  , return/1
                  ]).

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
            path   => "/banned/:who",
            func   => delete,
            descr  => "Delete banned"}).

-export([ list/2
        , create/2
        , delete/2
        ]).

list(_Bindings, Params) ->
    return({ok, emqx_mgmt_api:paginate(emqx_banned, Params, fun format/1)}).

create(_Bindings, Params) ->
    case pipeline(Params, create, [fun ensure_required/2,
                                   fun validate_params/2,
                                   fun pack_banned/2]) of
        {ok, Banned} ->
            ok = emqx_mgmt:create_banned(Banned),
            return({ok, Params});
        {error, Code, Message} -> 
            return({error, Code, Message})
    end.

delete(#{who := Who}, Params) ->
    case pipeline(Params, delete, [fun ensure_required/2,
                                   fun validate_params/2,
                                   fun fetch_as/2]) of
        {ok, <<"ip_address">>} ->
            emqx_mgmt:delete_banned({ip_address, inet:parse_address(str(Who))}),
            return();
        {ok, <<"username">>} ->
            emqx_mgmt:delete_banned({username, bin(Who)}),
            return();
        {ok, <<"client_id">>} ->
            emqx_mgmt:delete_banned({client_id, bin(Who)}),
            return();
        {error, Code, Message} -> 
            return({error, Code, Message})
    end.

%% Go through plugs in pipeline
pipeline(Params, _Action, []) ->
    {ok, Params};
pipeline(Params, Action, [Plug | PlugList]) ->
    case Plug(Params, Action) of
        {ok, NewParams} ->
            pipeline(NewParams, Action, PlugList);
        {error, Code, Message} ->
            {error, Code, Message}
    end.

%% Plugs
ensure_required(Params, Action) when is_list(Params) ->
    #{required_params := RequiredParams, message := Msg} = required_params(Action),
    AllIncluded = lists:all(fun(Key) ->
                      lists:keymember(Key, 1, Params)
                  end, RequiredParams),
    case AllIncluded of
        true -> {ok, Params};
        false ->
            {error, ?ERROR7, Msg}
    end.

validate_params(Params, _Action) ->
    #{enum_values := AsEnums, message := Msg} = enum_values(as),
    case lists:member(get_value(<<"as">>, Params), AsEnums) of
        true -> {ok, Params};
        false ->
            {error, ?ERROR8, Msg}
    end.

pack_banned(Params, _Action) ->
    do_pack_banned(Params, #banned{}).

do_pack_banned([], Banned) ->
    {ok, Banned};
do_pack_banned([{<<"who">>, Who} | Params], Banned) ->
    case lists:keytake(<<"as">>, 1, Params) of
        {value, {<<"as">>, <<"ip_address">>}, Params2} ->
            {ok, IPAddress} = inet:parse_address(str(Who)),
            do_pack_banned(Params2, Banned#banned{who = {ip_address, IPAddress}});
        {value, {<<"as">>, <<"client_id">>}, Params2} ->
            do_pack_banned(Params2, Banned#banned{who = {client_id, Who}});
        {value, {<<"as">>, <<"username">>}, Params2} ->
            do_pack_banned(Params2, Banned#banned{who = {username, Who}})
    end;
do_pack_banned([P1 = {<<"as">>, _}, P2 | Params], Banned) ->
    do_pack_banned([P2, P1 | Params], Banned);
do_pack_banned([{<<"reason">>, Reason} | Params], Banned) ->
    do_pack_banned(Params, Banned#banned{reason = Reason});
do_pack_banned([{<<"by">>, By} | Params], Banned) ->
    do_pack_banned(Params, Banned#banned{by = By});
do_pack_banned([{<<"desc">>, Desc} | Params], Banned) ->
    do_pack_banned(Params, Banned#banned{desc = Desc});
do_pack_banned([{<<"until">>, Until} | Params], Banned) ->
    do_pack_banned(Params, Banned#banned{until = Until});
do_pack_banned([_P | Params], Banned) -> %% ingore other params
    do_pack_banned(Params, Banned).

fetch_as(Params, _Action) ->
    {ok, get_value(<<"as">>, Params)}.

required_params(create) ->
    #{required_params => [<<"who">>, <<"as">>],
      message => <<"missing mandatory params: ['who', 'as']">> };
required_params(delete) ->
  #{required_params => [<<"as">>],
    message => <<"missing mandatory params: ['as']">> }.

enum_values(as) ->
    #{enum_values => [<<"client_id">>, <<"username">>, <<"ip_address">>],
      message => <<"value of 'as' must be one of: ['client_id', 'username', 'ip_address']">> }.

%% Internal Functions

format(BannedList) when is_list(BannedList) ->
    [format(Ban) || Ban <- BannedList];
format(#banned{who = {ip_address, IpAddr}, reason = Reason, desc = Desc, by = By,
               until = Until}) ->
    #{who => bin(inet:ntoa(IpAddr)), as => <<"ip_address">>, reason => Reason, desc => Desc, by => By, until => Until};
format(#banned{who = {As, Who}, reason = Reason, desc = Desc, by = By, until = Until}) ->
    #{who => Who, as => As, reason => Reason, desc => Desc, by => By, until => Until}.

bin(L) when is_list(L) ->
    list_to_binary(L);
bin(B) when is_binary(B) ->
    B.

str(B) when is_binary(B) ->
    binary_to_list(B);
str(L) when is_list(L) ->
    L.
