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

-module(emqx_mgmt_api_log).

-include("emqx_mgmt.hrl").

-import(proplists, [ get_value/2
                   , get_value/3
                   ]).

-import(minirest, [return/1]).

-rest_api(#{name   => get_primary_log_level,
            method => 'GET',
            path   => "/log",
            func   => get_primary_log_level,
            descr  => "get primary log level"}).

-rest_api(#{name   => set_primary_log_level,
            method => 'PUT',
            path   => "/log",
            func   => set_primary_log_level,
            descr  => "set primary log level"}).

-rest_api(#{name   => trace_list,
            method => 'GET',
            path   => "/log/trace",
            func   => trace_list,
            descr  => "get trace list"}).

-rest_api(#{name   => trace_on,
            method => 'POST',
            path   => "/log/trace",
            func   => trace_on,
            descr  => "create trace"}).

-rest_api(#{name   => trace_info,
            method => 'GET',
            path   => "/log/trace/:bin:type/:bin:name",
            func   => trace_info,
            descr  => "view trace log"}).

-rest_api(#{name   => trace_off,
            method => 'DELETE',
            path   => "/log/trace/:bin:type/:bin:name",
            func   => trace_off,
            descr  => "delete trace"}).

-rest_api(#{name   => trace_view,
            method => 'GET',
            path   => "/log/trace/view/:bin:type/:bin:name",
            func   => trace_view,
            descr  => "view trace log"}).

-rest_api(#{name   => trace_download,
            method => 'GET',
            path   => "/log/trace/download/:bin:type/:bin:name",
            func   => trace_download,
            descr  => "download trace log"}).

-export([ get_primary_log_level/2
        , set_primary_log_level/2
        , trace_list/2
        , trace_on/2
        , trace_info/2
        , trace_off/2
        , trace_view/2
        , trace_download/2
        ]).

get_primary_log_level(_, _) ->
    Data = #{primary_level => emqx_logger:get_primary_log_level()},
    return({ok, Data}).

set_primary_log_level(_, Params) ->
    Level = get_value(<<"primary_level">>, Params),
    case validate([level], [Level]) of
        ok ->
            lists:foreach(fun(Node) ->
                                  rpc:call(Node, emqx_logger, set_primary_log_level, [binary_to_atom(Level, utf8)])
                          end, ekka_mnesia:running_nodes()),
            return(ok);
        Err -> return(Err)
    end.

trace_list(_, _) ->
    return({ok, get_all_tracce()}).

trace_on(_, Params) ->
    Type = get_value(<<"type">>, Params),
    Name = get_value(<<"name">>, Params),
    Level = get_value(<<"level">>, Params),
    File = get_value(<<"file">>, Params, <<"">>),
    case validate([type, name, level], [Type, Name, Level]) of
        ok ->
            LogFile = case byte_size(File) > 0 of
                          true -> binary_to_list(File);
                          false ->
                              FileName = re:replace(
                                           <<Type/binary, <<"_">>/binary, Name/binary, <<"_">>/binary, Level/binary>>,
                                           "/", "_",
                                           [{return, list}, global, unicode]
                                          ),
                              {logger, L} = lists:keyfind(logger, 1, application:get_all_env(kernel)),
                              {handler, file, _, #{config := #{file := ConfigLogFile}}} = lists:keyfind(file, 2, L),
                              FilePath = filename:dirname(ConfigLogFile),
                              filename:join(FilePath, FileName)
                      end,
            return(emqx_tracer:start_trace({binary_to_atom(Type, utf8), Name},
                                           binary_to_atom(Level, utf8),
                                           LogFile
                                          ));
        Err -> return(Err)
    end.

trace_info(#{type := Type, name := Name}, _) ->
    case get_trace(#{type => Type, name => Name}) of
        [] -> return({error, 404, trace_not_found});
        Trace -> return({ok, Trace})
    end.

trace_off(#{type := Type, name := Name}, _) ->
    case get_trace(#{type => Type, name => Name}) of
        [] -> return(ok);
        [#{node := Node}] ->
            return(rpc:call(Node, emqx_tracer, stop_trace, [{binary_to_atom(Type, utf8), http_uri:decode(Name)}]))
    end.

trace_view(#{type := Type, name := Name}, _) ->
    case get_trace(#{type => Type, name => Name}) of
        [] -> return({error, 404, trace_not_found});
        [#{node := Node, file := File}] ->
            return(rpc:call(Node, file, read_file, [File]))
    end.

trace_download(#{type := Type, name := Name}, _) ->
    case get_trace(#{type => Type, name => Name}) of
        [] -> return({error, 404, trace_not_found});
        [#{node := Node, file := File}] ->
            rpc:call(Node, minirest, return_file, [File])
    end.

get_trace(#{type := Type, name := Name}) ->
    lists:filter(
       fun(#{type := T, name := N}) ->
               atom_to_binary(T, utf8) =:= Type
               andalso N =:= http_uri:decode(Name)
       end, get_all_tracce()).

get_all_tracce() ->
    lists:append(
        lists:map(fun(Node) ->
                    [#{node  => Node,
                       type  => Type,
                       name  => iolist_to_binary(Name),
                       level => Level,
                       file  => iolist_to_binary(LogFile)
                       } || {{Type, Name}, {Level, LogFile}} <- rpc:call(Node, emqx_tracer, lookup_traces, [])]
                  end, ekka_mnesia:running_nodes())).

validate([], []) ->
   ok;
validate([K|Keys], [V|Values]) ->
   case do_validation(K, V) of
       false -> {error, K};
       true  -> validate(Keys, Values)
   end.

do_validation(type, <<"clientid">>) -> true;
do_validation(type, <<"topic">>) -> true;
do_validation(name, Name) when is_binary(Name)
                       andalso byte_size(Name) > 0 -> true;
do_validation(level, Level) when is_binary(Level)
                       andalso byte_size(Level) > 0 ->
    Level =:= <<"emergency">> orelse
    Level =:= <<"alert">> orelse
    Level =:= <<"critical">> orelse
    Level =:= <<"error">> orelse
    Level =:= <<"warning">> orelse
    Level =:= <<"notice">> orelse
    Level =:= <<"info">> orelse
    Level =:= <<"debug">>;
do_validation(_, _) ->
    false.
