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

-module(emqx_mgmt_cli).

-include_lib("emqx/include/emqx_cli.hrl").

-export([load/0, cmd/1, unload/0]).

load() ->
    emqx_ctl:register_cmd(mgmt, {?MODULE, cmd}, []).

cmd(["add_app", AppId]) ->
    case emqx_mgmt_auth:add_app(list_to_binary(AppId)) of
        {ok, Secret} ->
            ?PRINT("AppSecret: ~s~n", [Secret]);
        {error, already_existed} ->
            ?PRINT_MSG("Error: already existed~n");
        {error, Reason} ->
            ?PRINT("Error: ~p~n", [Reason])
    end;

cmd(["del_app", AppId]) ->
    case emqx_mgmt_auth:del_app(list_to_binary(AppId)) of
        ok -> ?PRINT_MSG("ok~n");
        {error, not_found} ->
            ?PRINT_MSG("Error: app not found~n");
        {error, Reason} ->
            ?PRINT("Error: ~p~n", [Reason])
    end;

cmd(["list_apps"]) ->
    lists:foreach(fun({AppId, AppSecret}) ->
          ?PRINT("~s: ~s~n", [AppId, AppSecret])
      end, emqx_mgmt_auth:list_apps());

cmd(_) ->
    ?USAGE([{"mgmt add_app <AppId>", "Add Application of REST API"},
            {"mgmt del_app <AppId>", "Delete Application of REST API"},
            {"mgmt list_apps",       "List Applications"}]).

unload() ->
    emqx_ctl:unregister_cmd(cmd).

