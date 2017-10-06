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

-module(emq_mgmt_api_alarms).

-author("Feng Lee <feng@emqtt.io>").

-rest_api(#{name   => list_all_alarms,
            method => 'GET',
            path   => "/alarms/",
            func   => list,
            descr  => "List all alarms"}).

-rest_api(#{name   => list_node_alarms,
            method => 'GET',
            path   => "/alarms/:node",
            func   => list,
            descr  => "List alarms of a node"}).

-export([list/2]).

list(#{node := Node}, Params) ->
    {ok, format(emq_mgmt:get_alarms(Node))};
    
list(_Binding, Params) ->
    {ok, [{Node, format(Alarms)} || {Node, Alarms} <- emq_mgmt:get_alarms()]}.

format(Alarms) when is_list(Alarms) ->
    [format(Alarm) || Alarm <- Alarms];

format(#mqtt_alarm{id        = Id,
                   severity  = Severity,
                   title     = Title,
                   summary   = Summary,
                   timestamp = Ts}) ->
    #{id        => Id,
      severity  => Severity,
      title     => iolist_to_binary(Title),
      summary   => iolist_to_binary(Summary),
      timestamp => iolist_to_binary(emq_mgmt_util:strftime(Ts))}.

