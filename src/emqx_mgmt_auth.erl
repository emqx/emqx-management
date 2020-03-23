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

-module(emqx_mgmt_auth).

-include("emqx_mgmt.hrl").

% Mnesia Bootstrap
-export([mnesia/1]).
-boot_mnesia({mnesia, [boot]}).
-copy_mnesia({mnesia, [copy]}).

%% APP Management API
-export([ add_app/1
        , add_app/2
        , add_app/3
        , lookup_app/1
        , update_app/2
        , delete_app/1
        , list_apps/0
        ]).

%% APP Auth/ACL API
-export([is_authorized/2]).

-type(appid() :: binary()).

-type(appsecret() :: binary()).

%%--------------------------------------------------------------------
%% Mnesia Bootstrap
%%--------------------------------------------------------------------

mnesia(boot) ->
    ok = ekka_mnesia:create_table(app, [
                {disc_copies, [node()]},
                {record_name, app},
                {attributes, record_info(fields, app)}]);

mnesia(copy) ->
    ok = ekka_mnesia:copy_table(app, disc_copies).

%%--------------------------------------------------------------------
%% Manage Apps
%%--------------------------------------------------------------------
% -spec(add_default_app() -> ok | {ok, appsecret()} | {error, term()}).
% add_default_app() ->
%     AppID = application:get_env(?APP, default_application_id, undefined),
%     AppSecret = application:get_env(?APP, default_application_secret, undefined),
%     case {AppID, AppSecret} of
%         {undefined, _} -> ok;
%         {_, undefined} -> ok;
%         {_, _} ->
%             AppId1 = erlang:list_to_binary(AppID),
%             AppSecret1 = erlang:list_to_binary(AppSecret),
%             add_app(AppId1, <<"Default">>, AppSecret1, <<"Application user">>, true, undefined)
%     end.

add_app(Opts) when is_list(Opts) ->
    AddID = genrate_appid(),
    %% TODO: Check is appid existing
    AppSecret = genrate_appsecret(),
    add_app(AddID, AppSecret, Opts).

add_app(AppID, AppSecret) when is_binary(AppID) andalso is_binary(AppSecret) ->
    add_app(AppID, AppSecret, default_opts()).

add_app(AppID, AppSecret, Opts) ->
    NOpts = lists:ukeymerge(1, Opts, default_opts()),
    App = #app{id = AppID,
               secret = AppSecret,
               enabled = enabled(NOpts),
               expired = expired(NOpts)},
    AddFun = fun() ->
                 case mnesia:wread({app, AppID}) of
                     [] -> mnesia:write(App);
                     _  -> mnesia:abort(alread_existed)
                 end
             end,
    case mnesia:transaction(AddFun) of
        {atomic, ok} -> {ok, AppID, AppSecret};
        {aborted, Reason} -> {error, Reason}
    end.

genrate_appid() ->
    <<>>.

genrate_appsecret() ->
    <<>>.

default_opts() ->
    [{enabled, true}, {expired, 0}].

enabled(Opts) ->
    proplists:get_value(enabled, Opts).

expired(Opts) ->
    proplists:get_value(expired, Opts).

-spec(lookup_app(appid()) -> {{appid(), appsecret(), binary(), binary(), boolean(), integer() | undefined} | undefined}).
lookup_app(AppID) when is_binary(AppID) ->
    case mnesia:dirty_read(app, AppID) of
        [App] -> App;
        [] -> {error, not_found}
    end.

update_app(AppID, Opts) ->
    case mnesia:dirty_read(app, AppID) of
        [App = #app{}] ->
            NApp = App#app{enabled = proplists:get_value(enabled, Opts, App#app.enabled),
                           expired = proplists:get_value(expired, Opts, App#app.expired)},
            case mnesia:transaction(fun() -> mnesia:write(NApp) end) of
                {atomic, ok} -> ok;
                {aborted, Reason} -> {error, Reason}
            end;
        [] ->
            {error, not_found}
    end.

delete_app(AppID) ->
    case mnesia:transaction(fun mnesia:delete/1, [{app, AppID}]) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.


% -spec(list_apps() -> [{appid(), appsecret(), binary(), binary(), boolean(), integer() | undefined}]).
list_apps() ->
    ets:tab2list(app).

%%--------------------------------------------------------------------
%% Authenticate App
%%--------------------------------------------------------------------

-spec(is_authorized(appid(), appsecret()) -> boolean()).
is_authorized(AppID, AppSecret) ->
    case lookup_app(AppID) of
        #app{secret = AppSecret0, enabled = Enabled, expired = Expired} ->
            Enabled andalso is_not_expired(Expired) andalso AppSecret =:= AppSecret0;
        _ ->
            false
    end.

is_not_expired(0) ->
    true;
is_not_expired(Expired) ->
    Expired >= erlang:system_time(second).

