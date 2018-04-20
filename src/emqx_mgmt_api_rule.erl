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

-module(emqx_mgmt_api_rule).

-include_lib("emqx/include/emqx.hrl").

-import(proplists, [get_value/2, get_value/3]).

-import(emqx_web_hook_rule, [serialize/1, serialize/2]).

-rest_api(#{name   => create_rule,
            method => 'POST',
            path   => "/rules/",
            func   => create,
            descr  => "Create rule"}).

-rest_api(#{name   => update_rule,
            method => 'PUT',
            path   => "/rules/:int:id",
            func   => update,
            descr  => "Update rule"}).

-rest_api(#{name   => delete_rule,
            method => 'DELETE',
            path   => "/rules/:int:id",
            func   => delete,
            descr  => "Delete rule"}).


-export([create/2, update/2, delete/2]).

create(_Bindings, Params) ->
    %% TODO: Need check groupId or productId is right?
    case check_required_params(Params, create_required_params()) of
        {error, Reason} -> {error, list_to_binary(Reason)};
        ok ->
            emqx_web_hook_rule:insert(serialize(Params))
    end.

update(#{id := Id}, Params) ->
    %% FIXME: when modify ruleType, need config?
    emqx_web_hook_rule:update(serialize(Id, Params)).

delete(#{id := Id}, _Params) ->
    emqx_web_hook_rule:delete(Id).

%%--------------------------------------------------------------------
%% Interval functions
%%--------------------------------------------------------------------

check_required_params(_, []) -> ok;
check_required_params(Params, [Key | Rest]) ->
    case lists:keytake(Key, 1, Params) of
        {value, _, NewParams} -> check_required_params(NewParams, Rest);
        false                 -> {error, binary_to_list(Key) ++ " must be specified"}
    end.

create_required_params() ->
    [<<"id">>, <<"ruleType">>, <<"enable">>, <<"tenantID">>, <<"config">>].

