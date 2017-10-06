%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
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

-module(emq_mgmt_SUITE).

-compile(export_all).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("common_test/include/ct.hrl").

all() ->
    [{group, manage_apps},
     {group, check_apps}].

groups() ->
    [{manage_apps, [sequence],
      [t_add_app,
       t_del_app
      ]},
     {check_apps, [sequence],
      [t_check_app,
       t_check_app_acl
      ]}].

init_per_suite(Config) ->
    ekka_mnesia:start(),
    Config.

end_per_suite(_Config) ->
    application:stop(mnesia).

t_add_app(_Config) ->
    emqttd_rest_auth:add_app(id, <<"secret">>),
    ?assert(emqttd_rest_auth:check_app(id, <<"secret">>)),
    ?assertEqual(<<"secret">>, emqttd_rest_auth:get_appsecret(id)),
    ?assertEqual([{id, <<"secret">>}], emqttd_rest_auth:list_apps()),
    emqttd_rest_auth:del_app(id),
    ok.

t_del_app(_Config) ->
    ok.

t_check_app(_Config) ->
    ok.

t_check_app_acl(_Config) ->
    ok.


