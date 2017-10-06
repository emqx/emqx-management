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

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_internal.hrl").

-export([start_listeners/0, stop_listeners/0, handle_request/2]).

%%--------------------------------------------------------------------
%% Start/Stop Listeners
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun start_listener/1, listeners()).
    
stop_listeners() ->
    lists:foreach(fun stop_listener/1, listeners()).

start_listener({Proto, Port, Options}) when Proto == http orelse Proto == https ->
    mochiweb:start_http(listener_name(Proto), Port, Options, rest_handler()).

stop_listener({Proto, Port, _}) ->
    mochiweb:stop_http(listener_name(Proto), Port).

listeners() ->
    application:get_env(emqx_management, listeners, []).
    
listener_name(Proto) ->
    list_to_atom("management:" ++ atom_to_list(Proto)).

%%--------------------------------------------------------------------
%% REST Handler and Dispatcher
%%--------------------------------------------------------------------

rest_handler() ->
    {?MODULE, handle_request, [rest_dispatcher(rest_apis())]}.

handle_request(Req, Dispatch) ->
    Method = Req:get(method),
    case Req:get(path) of
        "/status" when Method =:= 'HEAD'; Method =:= 'GET' ->
            {InternalStatus, _ProvidedStatus} = init:get_status(),
            AppStatus = case lists:keysearch(emqttd, 1, application:which_applications()) of
                false         -> not_running;
                {value, _Val} -> running
            end,
            Status = io_lib:format("Node ~s is ~s~nemqttd is ~s",
                                    [node(), InternalStatus, AppStatus]),
            Req:ok({"text/plain", Status});
        "/" when Method =:= 'HEAD'; Method =:= 'GET' ->
            respond(Req, 200, [ [{method, M}, {path, iolist_to_binary(["api/v2/", P])}]
                                || #{method := M, path := P} <- rest_apis() ]);
        "/api/v2/" ++ Url ->
            if_authorized(Req, fun() -> Dispatch(Method, Url, Req) end);
        _ ->
            respond(Req, 404, [])
    end.

rest_dispatcher(APIs) ->
    fun(Method, Url, Req) ->
        case match_api(Method, Url, APIs) of
            {ok, #{module := Mod, func := Fun, bindings := Bindings}} ->
                case parse_params(Req) of
                    {ok, Params} ->
                        lager:debug("Mod: ~s, Fun: ~s, Bindings: ~p, Params: ~p", [Mod, Fun, Bindings, Params]),
                        try
                            apply(Mod, Fun, [Bindings, Params])
                        of
                            ok ->
                                respond(Req, 200, [{code, ?SUCCESS}]);
                            {ok, Data} ->
                                respond(Req, 200, [{code, ?SUCCESS}, {result, Data}]);
                            {error, Reason} ->
                                respond(Req, 500, [{reason, Reason}])
                        catch
                            _:Reason ->
                                lager:error("Execute API '~s' Error: ~p", [Url, Reason]),
                                respond(Req, 500, [{reason, Reason}])
                        end;
                    {error, Reason} ->
                        respond(Req, 400, Reason)
                end;
            false ->
                respond(Req, 404, [])
        end
    end.

rest_apis() ->
    lists:usort(
      lists:append(
        [API#{module => Module, tokens => string:tokens(Path, "/")} ||
         {ok, Module} <- [application:get_key(emqx_management, modules)],
         {rest_api, [API = #{path := Path}]} <- Module:module_info(attributes)])).

match_api(_Method, _Url, []) ->
    false;
match_api(Method, Url, [API|APIs]) ->
    case match_api(Method, Url, API) of
        {ok, Binding} -> {ok, API#{binding => Binding}};
        false -> match_api(Method, Url, APIs)
    end;
match_api(Method, Url, #{method := Method, tokens := Tokens}) ->
    match_path(string:tokens(Url, "/"), Tokens, #{});
match_api(_Method, _Url, _API) ->
    false.

match_path([], [], Bindings) ->
    {ok, Bindings};
match_path([], [_H|_T], _) ->
    false;
match_path([_H|_T], [], _) ->
    false;
match_path([H1|T1], [":node"|T2], Bindings) ->
    match_path(T1, T2, Bindings#{node => list_to_existing_atom(H1)});
match_path([H1|T1], [":" ++ H2|T2], Bindings) ->
    match_path(T1, T2, Bindings#{list_to_atom(H2) => H1});
match_path([H|T1], [H|T2], Bindings) ->
    match_path(T1, T2, Bindings).

if_authorized(Req, Fun) ->
    case is_authorized(Req) of true -> Fun(); false -> respond(Req, 401,  []) end.

is_authorized(Req) ->
    case Req:get_header_value("Authorization") of
        undefined -> false;
        "Basic " ++ BasicAuth ->
            {AppId, AppSecret} = user_passwd(BasicAuth),
            case emqx_mgmt_auth:is_authorized(AppId, AppSecret) of
                ok -> true;
                {error, Reason} ->
                    lager:error("Auth failure: appid=~s, reason=~p", [AppId, Reason]),
                    false
            end
    end.

user_passwd(BasicAuth) ->
    list_to_tuple(binary:split(base64:decode(BasicAuth), <<":">>)).

respond(Req, 401, Data) ->
    Req:respond({401, [{"WWW-Authenticate", "Basic Realm=\"emqx management\""}], Data});
respond(Req, 404, Data) ->
    Req:respond({404, [{"Content-Type", "text/plain"}], Data});
respond(Req, Code, Data) when Code == 200 orelse Code == 500 ->
    Req:respond({Code, [{"Content-Type", "application/json"}], to_json(Data)});
respond(Req, Code, Data) ->
    Req:respond({Code, [{"Content-Type", "text/plain"}], Data}).

parse_params(Req) ->
    case Req:get(method) of
        'GET'   -> mochiweb_request:parse_qs(Req);
        _Method -> case Req:recv_body() of
                       <<>> -> [];
                       undefined -> [];
                       Body -> parse_json(Body)
                   end
    end.

parse_json(Body) ->
    case jsx:is_json(Body) of
        true  -> jsx:decode(Body);
        false -> {error, <<"Invalid Json">>}
    end.

to_json([])   -> <<"[]">>;
to_json(Data) -> jsx:encode(Data).

