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

-module(emqx_mgmt_api_telemetry).

-rest_api(#{name   => enable_telemetry,
            method => 'PUT',
            path   => "/telemetry/status",
            func   => enable,
            descr  => "Enable or disbale telemetry"}).

-rest_api(#{name   => get_telemetry_status,
            method => 'GET',
            path   => "/telemetry/status",
            func   => get_status,
            descr  => "Get telemetry status"}).

-rest_api(#{name   => get_telemetry_data,
            method => 'GET',
            path   => "/telemetry/data",
            func   => get_data,
            descr  => "Get reported telemetry data"}).

-export([ enable/2
        , get_status/2
        , get_data/2
        ]).

-import(minirest, [return/1]).

enable(_Bindings, Params) ->
    case proplists:get_value(<<"enabled">>, Params) of
        true ->
            emqx_mgmt:enable_telemetry(),
            return(ok);
        false ->
            emqx_mgmt:disable_telemetry(),
            return(ok);
        undefined ->
            return({error, missing_required_params})
    end.

get_status(_Bindings, _Params) ->
    return({ok, emqx_mgmt:get_telemetry_status()}).

get_data(_Bindings, _Params) ->
    return(emqx_mgmt:get_telemetry_data()).