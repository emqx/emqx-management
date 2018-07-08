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

-module(emqx_mgmt_http).

-author("Feng Lee <feng@emqtt.io>").

-export([start_listeners/0, handle_request/2, stop_listeners/0]).

-define(APP, emqx_management).

-define(EXCEPT, [add_app, del_app, list_apps, lookup_app, update_app]).

%%--------------------------------------------------------------------
%% Start/Stop Listeners
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun start_listener/1, listeners()).
    
stop_listeners() ->
    lists:foreach(fun stop_listener/1, listeners()).

start_listener({Proto, Port, Options}) when Proto == http orelse Proto == https ->
    Handlers = [{"/status", {?MODULE, handle_request, []}},
                {"/api/v2", minirest:handler(#{apps => [?APP], except => ?EXCEPT }),
                 [{authorization, fun authorize_appid/1}]}],
    minirest:start_http(listener_name(Proto), Port, Options, Handlers).

stop_listener({Proto, Port, _}) ->
    minirest:stop_http(listener_name(Proto), Port).

listeners() ->
    application:get_env(?APP, listeners, []).
    
listener_name(Proto) ->
    list_to_atom("management:" ++ atom_to_list(Proto)).

%%--------------------------------------------------------------------
%% Handle 'status' request
%%--------------------------------------------------------------------

handle_request(Path, Req) ->
    handle_request(Req:get(method), Path, Req).

handle_request('GET', "/", Req) ->
    {InternalStatus, _ProvidedStatus} = init:get_status(),
    AppStatus = case lists:keysearch(emqx, 1, application:which_applications()) of
        false         -> not_running;
        {value, _Val} -> running
    end,
    Status = io_lib:format("Node ~s is ~s~nemqx is ~s",
                            [node(), InternalStatus, AppStatus]),
    Req:ok({"text/plain", Status});

handle_request(_Method, _Path, Req) ->
    Req:not_found().

authorize_appid(Req) ->
    case Req:get_header_value("Authorization") of
        undefined -> is_actor_from(Req);
        "Basic " ++ BasicAuth ->
            {AppId, AppSecret} = user_passwd(BasicAuth),
            emqx_mgmt_auth:is_authorized(AppId, AppSecret)
    end.

is_actor_from(Req) ->
    {Path0, _, _} = mochiweb_util:urlsplit_path(Req:get(raw_path)),
    case Path0 of
        "/api/v2/dmp/publish" -> true;
        "/api/v2/dmp/publish_lwm2m" -> true;
        _ -> false
    end.
user_passwd(BasicAuth) ->
    list_to_tuple(binary:split(base64:decode(BasicAuth), <<":">>)).

