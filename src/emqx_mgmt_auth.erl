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

-module(emqx_mgmt_auth).

%% Mnesia Bootstrap
-export([mnesia/1]).
-boot_mnesia({mnesia, [boot]}).
-copy_mnesia({mnesia, [copy]}).

%% APP Management API
-export([add_app/3, lookup_app/1, get_appsecret/1, update_app/3, del_app/1, list_apps/0]).

%% APP Auth/ACL API
-export([is_authorized/2]).

-record(mqtt_app, {id, secret, name, desc}).

-type(appid() :: binary()).

-type(appsecret() :: binary()).

%%--------------------------------------------------------------------
%% Mnesia Bootstrap
%%--------------------------------------------------------------------

mnesia(boot) ->
    ok = ekka_mnesia:create_table(mqtt_app, [
                {disc_copies, [node()]},
                {record_name, mqtt_app},
                {attributes, record_info(fields, mqtt_app)}]);

mnesia(copy) ->
    ok = ekka_mnesia:copy_table(mqtt_app, disc_copies).

%%--------------------------------------------------------------------
%% Manage Apps
%%--------------------------------------------------------------------

-spec(add_app(appid(), binary(), binary()) -> {ok, appsecret()} | {error, term()}).
add_app(AppId, Name, Desc) when is_binary(AppId) ->
    Secret = emqx_guid:to_base62(emqx_guid:gen()),
    App = #mqtt_app{id = AppId, secret = Secret, name = Name, desc = Desc},
    AddFun = fun() ->
                 case mnesia:wread({mqtt_app, AppId}) of
                     [] -> mnesia:write(App);
                     _  -> mnesia:abort(alread_existed)
                 end
             end,
    case mnesia:transaction(AddFun) of
        {atomic, ok} -> {ok, Secret};
        {aborted, Reason} -> {error, Reason}
    end.

-spec(get_appsecret(appid()) -> {appsecret() | undefined}).
get_appsecret(AppId) when is_binary(AppId) ->
    case mnesia:dirty_read(mqtt_app, AppId) of
        [#mqtt_app{secret = Secret}] -> Secret;
        [] -> undefined
    end.

-spec(lookup_app(appid()) -> {{appid(), appsecret(), binary, binary} | undefined}).
lookup_app(AppId) when is_binary(AppId) ->
    case mnesia:dirty_read(mqtt_app, AppId) of
        [#mqtt_app{id = AppId, secret = AppSecret, name = Name, desc = Desc}] -> {AppId, AppSecret, Name, Desc};
        [] -> undefined
    end.

-spec(update_app(appid(), binary(), binary()) -> ok | {error, term()}).
update_app(AppId, Name, Desc) ->
    case mnesia:dirty_read(mqtt_app, AppId) of
        [App = #mqtt_app{}] ->
            case mnesia:transaction(fun() -> mnesia:write(App#mqtt_app{name = Name, desc = Desc}) end) of
                {atomic, ok} -> ok;
                {aborted, Reason} -> {error, Reason}
            end;
        [] ->
            {error, ont_found}
    end.

-spec(del_app(appid()) -> ok | {error, term()}).
del_app(AppId) when is_binary(AppId) ->
    case mnesia:transaction(fun mnesia:delete/1, [{mqtt_app, AppId}]) of
        {atomic, Ok} -> Ok;
        {aborted, Reason} -> {error, Reason}
    end.

-spec(list_apps() -> [{appid(), appsecret(), binary, binary}]).
list_apps() ->
    [ {AppId, AppSecret, Name, Desc} || #mqtt_app{id = AppId,
                                                  secret = AppSecret,
                                                  name = Name,
                                                  desc = Desc} <- ets:tab2list(mqtt_app) ].
%%--------------------------------------------------------------------
%% Authenticate App
%%--------------------------------------------------------------------

-spec(is_authorized(appid(), appsecret()) -> boolean()).
is_authorized(AppId, AppSecret) ->
    case get_appsecret(AppId) of AppSecret -> true; _ -> false end.

