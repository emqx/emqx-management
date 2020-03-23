-module(emqx_mgmt_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

-import(minirest, [pipeline/3]).

-import(minirest_req, [ reply/2
                      , reply/3
                      , reply/4
                      , serialize/2
                      , serialize_detail/2
                      , server_internal_error/3]).

execute(Req, Env) ->
    try pipeline([fun authorize/2,
                  fun filter/2], Req, Env)
    catch
        error:Error:Stacktrace ->
            io:format("Error: ~p, Stacktrace: ~p", [Error, Stacktrace]),
            {ok, server_internal_error(Error, Stacktrace, Req), Env}
    end.

authorize(Req, Env) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, AppId, AppSecret} ->
            case emqx_mgmt_auth:is_authorized(AppId, AppSecret) of
                true ->
                    {ok, Req, Env};
                false ->
                    {stop, unauthorized(Req)}
            end;
         _  -> {stop, unauthorized(Req)}
    end.

filter(Req, Env = #{handler_opts := #{handler := Module}}) ->
    {ok, App} = application:get_application(Module),
    case emqx_plugins:is_active(App) of
        true ->
            {ok, Req, Env};
        false ->
            {stop, forbidden(serialize("Plugin '~p' isn't running", [App]), Req)}
    end.

unauthorized(Req) ->
    reply(401, #{<<"www-authenticate">> => <<"Basic">>}, #{message => <<"Unauthorized">>}, Req).

forbidden(Message, Req) when is_binary(Message) ->
    reply(403, #{}, #{message => Message}, Req).


