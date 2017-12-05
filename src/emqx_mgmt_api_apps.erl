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

-module(emqx_mgmt_api_apps).

-author("Feng Lee <feng@emqtt.io>").

-import(proplists, [get_value/2, get_value/3]).

-rest_api(#{name   => add_app,
            method => 'POST',
            path   => "/apps/add_app",
            func   => add_app,
            descr  => "Add Application"}).

-rest_api(#{name   => del_app,
            method => 'DELETE',
            path   => "/apps/del_app/:bin:appid",
            func   => del_app,
            descr  => "Delete Application"}).

-rest_api(#{name   => list_apps,
            method => 'GET',
            path   => "/apps/list_apps",
            func   => list_apps,
            descr  => "List Applications"}).

-export([add_app/2, del_app/2, list_apps/2]).

add_app(_Bindings, Params) ->
    AppId = get_value(<<"app_id">>, Params),
    case emqx_mgmt_auth:add_app(AppId) of
        {ok, AppSecret} -> {ok, [{secret, AppSecret}]};
        Error -> return(Error)
    end.

del_app(#{appid := AppId}, _Params) ->
    return(emqx_mgmt_auth:del_app(AppId)).

list_apps(_Bindings, _Params) ->
    {ok, [format(Apps)|| Apps <- emqx_mgmt_auth:list_apps()]}.

format({AppId, AppSecret}) ->
    [{app_id, AppId}, {secret, AppSecret}].

return(ok) ->
    ok;
return({ok, _}) ->
    ok;
return({error, Reason}) ->
    {error, #{message => Reason}}.




