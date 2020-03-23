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

-module(emqx_mgmt_api_plugins).

-include_lib("emqx/include/emqx.hrl").

-export([ get/3
        , put/3
        ]).

-export([validate_operation/1]).

-export([ list_plugins/2
        , operate/4]).

-http_api(#{resource => "/plugins",
            allowed_methods => [<<"GET">>, <<"PUT">>],
            get => #{qs => [{<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}]},
            put => #{qs => [{<<"name">>, [atom]},
                            {<<"node">>, optional, [fun emqx_mgmt_api:validate_node/1]}],
                     body => [{<<"operation">>, [atom, fun ?MODULE:validate_operation/1]}]}}).

get(#{<<"node">> := Node}, _, _) ->
    case lists:member(Node, ekka_mnesia:cluster_nodes(all)) of
        false ->
            {200, []};
        true ->
            {200, list_plugins(Node)}
    end;
get(_, _, _) ->
    {200, list_plugins(ekka_mnesia:running_nodes())}.

put(#{<<"name">> := Name,
      <<"node">> := Node}, _, #{<<"operation">> := Operation}) ->
    case operate(Node, Operation, Name) of
        #{success := 0} = Details ->
            {400, #{message => <<"Failed to complete operation">>,
                    details => Details}};
        _ ->
            204
    end;
put(#{<<"name">> := Name}, _, #{<<"operation">> := Operation}) ->
    case operate(Operation, Name) of
        #{success := 0} = Details ->
            {400, #{message => <<"Failed to complete operation">>,
                    details => Details}};
        #{failed := 0} -> 204;
        Details ->
            {400, #{message => <<"Failed to complete all operations">>,
                    details => Details}}
    end.

list_plugins(Node) when is_atom(Node) ->
    list_plugins([Node]);
list_plugins(Nodes) when is_list(Nodes) ->
    list_plugins(Nodes, []).

list_plugins([], Acc) ->
    Acc;
list_plugins([Node | More], Acc) when Node =:= node() ->
    list_plugins(More, [#{node => Node, plugins => format(emqx_plugins:list())} | Acc]);
list_plugins(Nodes = [Node | _], Acc) ->
    emqx_mgmt_api:remote_call(Node, list_plugins, [Nodes, Acc]).

format(Plugins) ->
    format(Plugins, []).

format([], Acc) ->
    Acc;
format([#plugin{name = Name, descr = Descr, active = Active, type = Type} | More], Acc) ->
    NAcc = [#{name        => Name,
              description => iolist_to_binary(Descr),
              active      => Active,
              type        => Type} | Acc],
    format(More, NAcc).

operate(Operation, Name) ->
    operate(ekka_mnesia:running_nodes(), Operation, Name).

operate(Node, Operation, Name) when is_atom(Node) ->
    operate([Node], Operation, Name);
operate(Nodes, Operation, Name) when is_list(Nodes) ->
    operate(Nodes, Operation, Name, #{success => 0, failed => 0, errors => []}).

operate([], _, _, Acc) ->
    Acc;
operate([Node | More], Operation, Name, #{success := Success,
                                          failed := Failed,
                                          errors := Errors} = Acc) when Node =:= node() ->
    case Operation(Name) of
        ok ->
            operate(More, Operation, Name, Acc#{success := Success + 1});
        {error, Error} ->
            NErrors = [#{data => #{<<"operation">> => Operation,
                                   <<"name">> => Name,
                                   <<"node">> => Node}, error => Error} | Errors],
            operate(More, Operation, Name, Acc#{failed := Failed + 1, errors := NErrors})
    end;
operate(Nodes = [Node | _], Operation, Name, Acc) ->
    emqx_mgmt_api:remote_call(Node, operate, [Nodes, Operation, Name, Acc]).

load(Name) ->
    case emqx_plugin:load(Name) of
        ok -> ok;
        {error, already_started} -> ok;
        {error, not_found} -> {error, <<"The specified plugin was not found">>};
        {error, Reason} -> {error, minirest_req:serialize("Failed to load plugin due to ~p", [Reason])}
    end.

unload(Name) ->
    case emqx_plugin:unload(Name) of
        ok -> ok;
        {error, not_started} -> ok;
        {error, not_found} -> {error, <<"The specified plugin was not found">>};
        {error, Reason} -> {error, minirest_req:serialize("Failed to unload plugin due to ~p", [Reason])}
    end.

reload(Name) ->
    ok.
    % case emqx_plugin:reload(Name) of
    %     ok -> ok;
    %     {error, not_started} -> ok;
    %     {error, not_found} -> {error, <<"The specified plugin was not found">>};
    %     {error, Reason} -> {error, minirest_req:serialize("Failed to unload plugin due to ~p", [Reason])}
    % end.

validate_operation(Operation) ->
    case minirest:within(Operation, [load, unload, reload]) of
        true -> ok;
        false -> {error, not_valid_operation}
    end.