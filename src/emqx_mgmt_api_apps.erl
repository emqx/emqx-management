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

-module(emqx_mgmt_api_apps).

-include("emqx_mgmt.hrl").
-include_lib("emqx/include/emqx.hrl").

-export([ get/3
        , post/3
        , put/3
        , delete/3
        ]).

-http_api(#{resource => "/apps",
            allowed_methods => [<<"GET">>, <<"POST">>],
            post => #{body => [{<<"appid">>, optional, [nonempty]},
                               {<<"appsecret">>, optional, [nonempty]},
                               {<<"enabled">>, {optional, true}, [bool]},
                               {<<"expired">>, {optional, 0}, [int]}]}}).

-http_api(#{resource => "/apps/:appid",
            allowed_methods => [<<"GET">>, <<"PUT">>, <<"DELETE">>],
            get => #{bindings => [{<<"appid">>, [nonempty]}]},
            put => #{bindings => [{<<"appid">>, [nonempty]}],
                     body => [{[<<"enabled">>, <<"expired">>], [at_least_one]},
                              {<<"enabled">>, optional, [bool]},
                              {<<"expired">>, optional, [int]}]},
            delete => #{bindings => [{<<"appid">>, [nonempty]}]}}).

get(#{<<"appid">> := AppID}, _, _) ->
    case emqx_mgmt_auth:lookup(AppID) of
        {error, not_found} ->
            {404, #{message => <<"The specified application was not found">>}};
        App ->
            {200, format(App)}
    end;
get(_, _, _) ->
    {200, format(emqx_mgmt_auth:list_apps())}.

post(_, _, #{<<"appid">> := AppID,
             <<"appsecret">> := AppSecret,
             <<"enabled">> := Enabled,
             <<"expired">> := Expired}) ->
    case emqx_mgmt_auth:add_app(AppID, AppSecret, [{enabled, Enabled}, {expired, Expired}]) of
        {ok, AppID, AppSecret} ->
            {200, #{<<"appid">> => AppID, <<"appsecret">> => AppSecret}};
        {error, alread_existed} ->
            {409, #{message => <<"The specified AppID already exists">>}};
        {error, Reason} ->
            error(Reason)
    end;
post(_, _, #{<<"enabled">> := Enabled,
             <<"expired">> := Expired}) ->
    case emqx_mgmt_auth:add_app([{enabled, Enabled}, {expired, Expired}]) of
        {ok, AppID, AppSecret} ->
            {200, #{<<"appid">> => AppID, <<"appsecret">> => AppSecret}};
        {error, Reason} ->
            error(Reason)
    end.

put(#{<<"appid">> := AppID}, _, Body) ->
    case emqx_mgmt_auth:update_app(AppID, maps:to_list(Body)) of
        {ok, AppID, AppSecret} ->
            {200, #{<<"appid">> => AppID, <<"appsecret">> => AppSecret}};
        {error, not_found} ->
            %% TODO: Create a new application
            {400, #{message => <<"The specified AppID was not found">>}};
        {error, Reason} ->
            error(Reason)
    end.

delete(#{<<"appid">> := AppID}, _, _) ->
    case emqx_mgmt_auth:delete_app(AppID) of
        ok -> 204;
        {error, Reason} -> error(Reason)
    end.

format(Apps) when is_list(Apps) ->
    [format(App) || App <- Apps];
format(App) when is_record(App, app) ->
    #{<<"appid">> => App#app.id,
      <<"appsecret">> => App#app.secret,
      <<"enabled">> => App#app.enabled,
      <<"expired">> => App#app.expired}.

% validate_expired(Expired) ->
%     case Expired =< erlang:system_time(second) of
%         true ->
%             {error, };
%         false ->

%     end