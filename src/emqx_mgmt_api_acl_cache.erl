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

-module(emqx_mgmt_api_acl_cache).

-export([ get/3
        , post/3
        , delete/3
        ]).

-define(ALLOWED_METHODS, [<<"GET">>, <<"POST">>, <<"DELETE">>]).

-http_api(#{resource => "/acl-cache/setup",
            allowed_methods => [<<"PUT">>],
            put => #{body => [{<<"enabled">>, [bool]},
                               {<<"limit">>, {optional, 32}, [int]},
                               {<<"duration">>, {optional, 60}, [int]}]}}).

-http_api(#{resource => "/acl-cache/:clientid",
            allowed_methods => [<<"GET">>, <<"DELETE">>],
            get => #{bindings => [{<<"clientid">>, [nonempty]}]},
            delete => #{bindings => [{<<"clientid">>, [nonempty]}]}}).


get(#{<<"clientid">> := _ClientId}, _, _) ->
    204.

%% TODO: Delete post method
post(_, _, #{<<"enabled">> := true,
             <<"limit">> := _Limit,
             <<"duration">> := _Duration}) ->
    application:set_env(emqx, enable_acl_cache, true);
post(_, _, #{<<"enabled">> := false}) ->
    application:set_env(emqx, enable_acl_cache, false).

delete(#{<<"clientid">> := ClientId}, _, _) ->
    case delete_acl_cache(ClientId) of
        {error, not_found} ->
            {404, #{message => <<"The specified acl cache was not found">>}};
        ok ->
            204
    end.

%% TODO: Support paginate 
% list_acl_cache(ClientId) ->
%     case emqx_cm:lookup_channels(ClientId) of
%         [] -> {error, not_found};
%         Pids ->
%             list_acl_cache(ClientId, lists:last(Pids))
%     end.

delete_acl_cache(ClientId) ->
    delete_acl_cache(ekka_mnesia:running_nodes(), ClientId).

delete_acl_cache([], _) ->
    ok;
delete_acl_cache([Node | More], ClientId) when Node =:= node() ->
    case emqx_cm:lookup_channels(ClientId) of
        [] ->
            {error, not_found};
        Pids ->
            erlang:send(lists:last(Pids), clean_acl_cache),
            delete_acl_cache(More, ClientId)
    end;
delete_acl_cache(Nodes = [Node | _], ClientId) when Node =:= node() ->
    emqx_mgmt_api:remote_call(Node, delete_acl_cache, [Nodes, ClientId]).




