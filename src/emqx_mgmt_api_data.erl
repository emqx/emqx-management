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

-module(emqx_mgmt_api_data).

-include_lib("emqx/include/emqx.hrl").

-include_lib("kernel/include/file.hrl").

-include("emqx_mgmt.hrl").

-import(minirest, [ return/0
                  , return/1
                  ]).

-rest_api(#{name   => export,
            method => 'POST',
            path   => "/data/export",
            func   => export,
            descr  => "Export data"}).

-rest_api(#{name   => list_exported,
            method => 'GET',
            path   => "/data/export",
            func   => list_exported,
            descr  => "List exported file"}).

-rest_api(#{name   => import,
            method => 'POST',
            path   => "/data/import",
            func   => import,
            descr  => "Import data"}).

-rest_api(#{name   => download,
            method => 'GET',
            path   => "/data/file/:filename",
            func   => download,
            descr  => "Download data file to local"}).

-rest_api(#{name   => upload,
            method => 'POST',
            path   => "/data/file",
            func   => upload,
            descr  => "Upload data file from local"}).

-rest_api(#{name   => delete,
            method => 'DELETE',
            path   => "/data/file/:filename",
            func   => delete,
            descr  => "Delete data file"}).

-export([ export/2
        , list_exported/2
        , import/2
        , download/2
        , upload/2
        , delete/2
        ]).

-export([ get_list_exported/0
        , do_import/1
        ]).

export(_Bindings, _Params) ->
    Modules = emqx_mgmt:export_modules(),
    Rules = emqx_mgmt:export_rules(),
    Resources = emqx_mgmt:export_resources(),
    Blacklist = emqx_mgmt:export_blacklist(),
    Apps = emqx_mgmt:export_applications(),
    Users = emqx_mgmt:export_users(),
    AuthMnesia = emqx_mgmt:export_auth_mnesia(),
    AclMnesia = emqx_mgmt:export_acl_mnesia(),
    Schemas = emqx_mgmt:export_schemas(),
    {Configs, State} = emqx_mgmt:export_confs(),
    Seconds = erlang:system_time(second),
    {{Y, M, D}, {H, MM, S}} = emqx_mgmt_util:datetime(Seconds),
    Filename = io_lib:format("emqx-export-~p-~p-~p-~p-~p-~p.json", [Y, M, D, H, MM, S]),
    NFilename = filename:join([emqx:get_env(data_dir), Filename]),
    Version = emqx_sys:version(),
    Data = [{version, erlang:list_to_binary(Version)},
            {date, erlang:list_to_binary(emqx_mgmt_util:strftime(Seconds))},
            {modules, Modules},
            {rules, Rules},
            {resources, Resources},
            {blacklist, Blacklist},
            {apps, Apps},
            {users, Users},
            {auth_mnesia, AuthMnesia},
            {acl_mnesia, AclMnesia},
            {schemas, Schemas},
            {configs, Configs},
            {listeners_state, State}],

    Bin = emqx_json:encode(Data),
    ok = filelib:ensure_dir(NFilename),
    case file:write_file(NFilename, Bin) of
        ok ->
            case file:read_file_info(NFilename) of
                {ok, #file_info{size = Size, ctime = {{Y, M, D}, {H, MM, S}}}} ->
                    CreatedAt = io_lib:format("~p-~p-~p ~p:~p:~p", [Y, M, D, H, MM, S]),
                    return({ok, [{filename, list_to_binary(Filename)},
                                 {size, Size},
                                 {created_at, list_to_binary(CreatedAt)},
                                 {node, node()}
                                ]});
                {error, Reason} ->
                    return({error, Reason})
            end;
        {error, Reason} ->
            return({error, Reason})
    end.

list_exported(_Bindings, _Params) ->
    List = [ rpc:call(Node, ?MODULE, get_list_exported, []) || Node <- ekka_mnesia:running_nodes() ],
    NList = lists:map(fun({_, FileInfo}) -> FileInfo end, lists:keysort(1, lists:append(List))),
    return({ok, NList}).

get_list_exported() ->
    Dir = emqx:get_env(data_dir),
    {ok, Files} = file:list_dir_all(Dir),
    lists:foldl(
        fun(File, Acc) ->
            case filename:extension(File) =:= ".json" of
                true ->
                    FullFile = filename:join([Dir, File]),
                    case file:read_file_info(FullFile) of
                        {ok, #file_info{size = Size, ctime = CTime = {{Y, M, D}, {H, MM, S}}}} ->
                            CreatedAt = io_lib:format("~p-~p-~p ~p:~p:~p", [Y, M, D, H, MM, S]),
                            Seconds = calendar:datetime_to_gregorian_seconds(CTime),
                            [{Seconds, [{filename, list_to_binary(File)},
                                        {size, Size},
                                        {created_at, list_to_binary(CreatedAt)},
                                        {node, node()}
                                       ]} | Acc];
                        {error, Reason} ->
                            logger:error("Read file info of ~s failed with: ~p", [File, Reason]),
                            Acc
                    end;
                false -> Acc
            end
        end, [], Files).

import(_Bindings, Params) ->
    case proplists:get_value(<<"filename">>, Params) of
    undefined ->
        return({error, missing_required_params});
    Filename ->
        Result = case proplists:get_value(<<"node">>, Params) of
            undefined -> do_import(Filename);
            Node ->
                case lists:member(Node,
                      [ erlang:atom_to_binary(N, utf8) || N <- ekka_mnesia:running_nodes() ]
                     ) of
                    true -> rpc:call(erlang:binary_to_atom(Node, utf8), ?MODULE, do_import, [Filename]);
                    false -> return({error, no_existent_node})
                end
        end,
        return(Result)
    end.

do_import(Filename) ->
    FullFilename = filename:join([emqx:get_env(data_dir), Filename]),
    case file:read_file(FullFilename) of
        {ok, Json} ->
            Data = emqx_json:decode(Json, [return_maps]),
            Version = emqx_mgmt:to_version(maps:get(<<"version">>, Data)),
            case lists:member(Version, ?VERSIONS) of
                true  ->
                    try
                        emqx_mgmt:import_confs(maps:get(<<"configs">>, Data, []), maps:get(<<"listeners_state">>, Data, [])),
                        emqx_mgmt:import_resources(maps:get(<<"resources">>, Data, [])),
                        emqx_mgmt:import_rules(maps:get(<<"rules">>, Data, [])),
                        emqx_mgmt:import_blacklist(maps:get(<<"blacklist">>, Data, [])),
                        emqx_mgmt:import_applications(maps:get(<<"apps">>, Data, [])),
                        emqx_mgmt:import_users(maps:get(<<"users">>, Data, [])),
                        emqx_mgmt:import_modules(maps:get(<<"modules">>, Data, [])),
                        emqx_mgmt:import_auth_clientid(maps:get(<<"auth_clientid">>, Data, [])),
                        emqx_mgmt:import_auth_username(maps:get(<<"auth_username">>, Data, [])),
                        emqx_mgmt:import_auth_mnesia(maps:get(<<"auth_mnesia">>, Data, []), Version),
                        emqx_mgmt:import_acl_mnesia(maps:get(<<"acl_mnesia">>, Data, []), Version),
                        emqx_mgmt:import_schemas(maps:get(<<"schemas">>, Data, [])),
                        logger:debug("The emqx data has been imported successfully"),
                        ok
                    catch Class:Reason:Stack ->
                        logger:error("The emqx data import failed: ~0p", [{Class,Reason,Stack}]),
                        {error, import_failed}
                    end;
                false ->
                    logger:error("Unsupported version: ~p", [Version]),
                    {error, unsupported_version}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

download(#{filename := Filename}, _Params) ->
    FullFilename = filename:join([emqx:get_env(data_dir), Filename]),
    case file:read_file(FullFilename) of
        {ok, Bin} ->
            {ok, #{filename => list_to_binary(Filename),
                   file => Bin}};
        {error, Reason} ->
            return({error, Reason})
    end.

upload(Bindings, Params) ->
    do_upload(Bindings, maps:from_list(Params)).

do_upload(_Bindings, #{<<"filename">> := Filename,
                       <<"file">> := Bin}) ->
    FullFilename = filename:join([emqx:get_env(data_dir), Filename]),
    case file:write_file(FullFilename, Bin) of
        ok ->
            return({ok, [{node, node()}]});
        {error, Reason} ->
            return({error, Reason})
    end;
do_upload(Bindings, Params = #{<<"file">> := _}) ->
    Seconds = erlang:system_time(second),
    {{Y, M, D}, {H, MM, S}} = emqx_mgmt_util:datetime(Seconds),
    Filename = io_lib:format("emqx-export-~p-~p-~p-~p-~p-~p.json", [Y, M, D, H, MM, S]),
    do_upload(Bindings, Params#{<<"filename">> => Filename});
do_upload(_Bindings, _Params) ->
    return({error, missing_required_params}).

delete(#{filename := Filename}, _Params) ->
    FullFilename = filename:join([emqx:get_env(data_dir), Filename]),
    case file:delete(FullFilename) of
        ok ->
            return();
        {error, Reason} ->
            return({error, Reason})
    end.
