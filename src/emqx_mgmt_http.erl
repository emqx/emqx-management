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

-module(emqx_mgmt_http).

-import(proplists, [get_value/3]).

-export([ start_listeners/0
        , handle_request/2
        , stop_listeners/0
        ]).

-export([init/2]).

-include("emqx_mgmt.hrl").

% -include_lib("emqx/include/emqx.hrl").

% -define(APP, emqx_management).
% -define(EXCEPT_PLUGIN, [emqx_dashboard]).
% -ifdef(TEST).
% -define(EXCEPT, []).
% -else.
% -define(EXCEPT, [add_app, del_app, list_apps, lookup_app, update_app]).
% -endif.

%%--------------------------------------------------------------------
%% Start/Stop Listeners
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun({Proto, Port, Opts}) ->
                      %% TODO: use map
                      NOpts = normalize_opts([{proto, Proto},
                                              {port, Port}] ++ Opts),
                      Middlewares = minirest:default_middlewares() ++ [emqx_mgmt_middleware],
                      minirest:start_listener(listener_name(Proto), NOpts, Middlewares)
                  end, listeners()).

stop_listeners() ->
    lists:foreach(fun({Proto, _, _}) ->
                      minirest:stop_http(listener_name(Proto))
                  end, listeners()).

normalize_opts(Opts) ->
    lists:foldl(fun({inet6, true}, Acc) -> [inet6 | Acc];
                   ({inet6, false}, Acc) -> Acc;
                   ({ipv6_v6only, true}, Acc) -> [{ipv6_v6only, true} | Acc];
                   ({ipv6_v6only, false}, Acc) -> Acc;  %% Compat Windows OS
                   ({K, V}, Acc)-> [{K, V} | Acc]
                end, [], Opts).

listeners() ->
    application:get_env(?APP, listeners, []).

listener_name(Proto) ->
    list_to_atom(atom_to_list(Proto) ++ ":management").

%%--------------------------------------------------------------------
%% Handle 'status' request
%%--------------------------------------------------------------------
init(Req, Opts) ->
    Req1 = handle_request(cowboy_req:path(Req), Req),
    {ok, Req1, Opts}.

handle_request(Path, Req) ->
    handle_request(cowboy_req:method(Req), Path, Req).

handle_request(<<"GET">>, <<"/status">>, Req) ->
    {InternalStatus, _ProvidedStatus} = init:get_status(),
    AppStatus = case lists:keysearch(emqx, 1, application:which_applications()) of
        false         -> not_running;
        {value, _Val} -> running
    end,
    Status = io_lib:format("Node ~s is ~s~nemqx is ~s",
                            [node(), InternalStatus, AppStatus]),
    cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain">>}, Status, Req);

handle_request(_Method, _Path, Req) ->
    cowboy_req:reply(400, #{<<"content-type">> => <<"text/plain">>}, <<"Not found.">>, Req).

% authorize_appid(Req) ->
%     case cowboy_req:parse_header(<<"authorization">>, Req) of
%         {basic, AppId, AppSecret} -> emqx_mgmt_auth:is_authorized(AppId, AppSecret);
%          _  -> false
%     end.

% filter(#{app := App}) ->
%     case emqx_plugins:find_plugin(App) of
%         false -> false;
%         Plugin -> Plugin#plugin.active
%     end.
