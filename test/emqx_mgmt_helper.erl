%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_helper).

-compile(export_all).
-compile(nowarn_export_all).

-import(filename, [join/1]).

start_apps([]) ->
    ok;
start_apps([emqx_management | LeftApps]) ->
    start_app(emqx_management,
              local_path(join(["priv", "emqx_management.schema"])),
              local_path(join(["etc", "emqx_management.conf"]))),
    start_apps(LeftApps);
start_apps([App | LeftApps]) ->
    SchemaFile = deps_path(App, join(["priv", atom_to_list(App) ++ ".schema"])),
    ConfigFile = deps_path(App, join(["etc", atom_to_list(App) ++ ".conf"])),
    start_app(App, SchemaFile, ConfigFile),
    start_apps(LeftApps).

stop_apps(Apps) ->
    [application:stop(App) || App <- Apps].

start_app(App, SchemaFile, ConfigFile) ->
    read_schema_configs(App, SchemaFile, ConfigFile),
    set_special_configs(App),
    application:ensure_all_started(App).

local_path(RelativePath) ->
    deps_path(emqx_management, RelativePath).

deps_path(App, RelativePath) ->
    %% Note: not lib_dir because etc dir is not sym-link-ed to _build dir
    %% but priv dir is
    Path0 = code:priv_dir(App),
    Path = case file:read_link(Path0) of
               {ok, Resolved} -> Resolved;
               {error, _} -> Path0
           end,
    filename:join([Path, "..", RelativePath]).

read_schema_configs(App, SchemaFile, ConfigFile) ->
    ct:pal("Read configs - SchemaFile: ~p, ConfigFile: ~p", [SchemaFile, ConfigFile]),
    Schema = cuttlefish_schema:files([SchemaFile]),
    Conf = conf_parse:file(ConfigFile),
    NewConfig = cuttlefish_generator:map(Schema, Conf),
    Vals = proplists:get_value(App, NewConfig, []),
    [application:set_env(App, Par, Value) || {Par, Value} <- Vals].

set_special_configs(emqx) ->
    application:load(emqx_management),
    application:load(emqx_reloader),
    PluginsEtcDir = deps_path(emqx_management, "test/etc/"),
    application:set_env(emqx, plugins_etc_dir, PluginsEtcDir);
set_special_configs(_App) ->
    ok.
