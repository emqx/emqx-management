%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_mgmt_cli).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_mqtt.hrl").

-ifdef(TEST).
-define(PRINT_MSG(Msg), io_lib:format("~s", [Msg])).
-else.
-define(PRINT_MSG(Msg), io:format(Msg)).
-endif.

-ifdef(TEST).
-define(PRINT(Format, Args), io_lib:format(Format, Args)).
-else.
-define(PRINT(Format, Args), io:format(Format, Args)).
-endif.

-define(PRINT_CMD(Cmd, Descr), io:format("~-48s# ~s~n", [Cmd, Descr])).

-define(USAGE(CmdList), [?PRINT_CMD(Cmd, Descr) || {Cmd, Descr} <- CmdList]).

-import(lists, [foreach/2]).

-import(proplists, [get_value/2]).

-export([load/0]).

-export([status/1, broker/1, cluster/1, clients/1, sessions/1,
         routes/1, subscriptions/1, plugins/1, bridges/1,
         listeners/1, vm/1, mnesia/1, trace/1, log/1, acl/1, mgmt/1]).

-define(PROC_INFOKEYS, [status,
                        memory,
                        message_queue_len,
                        total_heap_size,
                        heap_size,
                        stack_size,
                        reductions]).

-define(MAX_LIMIT, 10000).

-define(APP, emqx).

-spec(load() -> ok).
load() ->
    Cmds = [Fun || {Fun, _} <- ?MODULE:module_info(exports), is_cmd(Fun)],
    lists:foreach(fun(Cmd) -> emqx_ctl:register_command(Cmd, {?MODULE, Cmd}, []) end, Cmds),
    emqx_mgmt_cli_cfg:register_config().

is_cmd(Fun) ->
    not lists:member(Fun, [init, load, module_info]).

mgmt(["insert", AppId, Name]) ->
    case emqx_mgmt_auth:add_app(list_to_binary(AppId), list_to_binary(Name)) of
        {ok, Secret} ->
            ?PRINT("AppSecret: ~s~n", [Secret]);
        {error, already_existed} ->
            ?PRINT_MSG("Error: already existed~n");
        {error, Reason} ->
            ?PRINT("Error: ~p~n", [Reason])
    end;

mgmt(["lookup", AppId]) ->
    case emqx_mgmt_auth:lookup_app(list_to_binary(AppId)) of
        {AppId1, AppSecret, Name, Desc, Status, Expired} ->
            ?PRINT("app_id: ~s~nsecret: ~s~nname: ~s~ndesc: ~s~nstatus: ~s~nexpired: ~p~n",
                           [AppId1, AppSecret, Name, Desc, Status, Expired]);
        undefined ->
            ?PRINT_MSG("Not Found.~n")
    end;

mgmt(["update", AppId, Status]) ->
    case emqx_mgmt_auth:update_app(list_to_binary(AppId), list_to_atom(Status)) of
        ok ->
            ?PRINT_MSG("update successfully.~n");
        {error, Reason} ->
            ?PRINT("Error: ~p~n", [Reason])
    end;

mgmt(["delete", AppId]) ->
    case emqx_mgmt_auth:del_app(list_to_binary(AppId)) of
        ok -> ?PRINT_MSG("ok~n");
        {error, not_found} ->
            ?PRINT_MSG("Error: app not found~n");
        {error, Reason} -> 
            ?PRINT("Error: ~p~n", [Reason])
    end;

mgmt(["list"]) ->
    lists:foreach(fun({AppId, AppSecret, Name, Desc, Status, Expired}) ->
        ?PRINT("app_id: ~s, secret: ~s, name: ~s, desc: ~s, status: ~s, expired: ~p~n",
                       [AppId, AppSecret, Name, Desc, Status, Expired])
    end, emqx_mgmt_auth:list_apps());

mgmt(_) ->
    emqx_cli:usage([{"mgmt list",                   "List Applications"},
                    {"mgmt insert <AppId> <Name>",   "Add Application of REST API"},
                    {"mgmt update <AppId> <status>", "Update Application of REST API"},
                    {"mgmt lookup <AppId>",          "Get Application of REST API"},
                    {"mgmt delete <AppId>",          "Delete Application of REST API"}]).

% configs(["set"]) ->
%     emqx_mgmt_cli_cfg:set_usage(), ok;

% configs(Cmd) when length(Cmd) > 2 ->
%     emqx_mgmt_cli_cfg:run(["config" | Cmd]), ok;

% configs(_) ->
%     emqx_cli:usage([{"configs set",                           "Show All configs Item"},
%                     {"configs set <Key>=<Value> --app=<app>", "Set Config Item"},
%                     {"configs show <Key> --app=<app>",        "show Config Item"}]).

%%--------------------------------------------------------------------
%% @doc Node status

status([]) ->
    {InternalStatus, _ProvidedStatus} = init:get_status(),
        ?PRINT("Node ~p is ~p~n", [node(), InternalStatus]),
    case lists:keysearch(?APP, 1, application:which_applications()) of
        false ->
            ?PRINT("~s is not running~n", [?APP]);
        {value, {?APP, _Desc, Vsn}} ->
            ?PRINT("~s ~s is running~n", [?APP, Vsn])
    end;
status(_) ->
     emqx_cli:usage("status", "Show broker status").

%%--------------------------------------------------------------------
%% @doc Query broker

broker([]) ->
    Funs = [sysdescr, version, uptime, datetime],
    foreach(fun(Fun) ->
                ?PRINT("~-10s: ~s~n", [Fun, emqx_sys:Fun()])
            end, Funs);

broker(["stats"]) ->
    foreach(fun({Stat, Val}) ->
                ?PRINT("~-20s: ~w~n", [Stat, Val])
            end, emqx_stats:getstats());

broker(["metrics"]) ->
    foreach(fun({Metric, Val}) ->
                ?PRINT("~-24s: ~w~n", [Metric, Val])
            end, lists:sort(emqx_metrics:all()));

broker(_) ->
    emqx_cli:usage([{"broker",         "Show broker version, uptime and description"},
                    {"broker stats",   "Show broker statistics of clients, topics, subscribers"},
                    {"broker metrics", "Show broker metrics"}]).

%%-----------------------------------------------------------------------------
%% @doc Cluster with other nodes

cluster(["join", SNode]) ->
    case ekka:join(ekka_node:parse_name(SNode)) of
        ok ->
            ?PRINT_MSG("Join the cluster successfully.~n"),
            cluster(["status"]);
        ignore ->
            ?PRINT_MSG("Ignore.~n");
        {error, Error} ->
            ?PRINT("Failed to join the cluster: ~p~n", [Error])
    end;

cluster(["leave"]) ->
    case ekka:leave() of
        ok ->
            ?PRINT_MSG("Leave the cluster successfully.~n"),
            cluster(["status"]);
        {error, Error} ->
            ?PRINT("Failed to leave the cluster: ~p~n", [Error])
    end;

cluster(["force-leave", SNode]) ->
    case ekka:force_leave(ekka_node:parse_name(SNode)) of
        ok ->
            ?PRINT_MSG("Remove the node from cluster successfully.~n"),
            cluster(["status"]);
        ignore ->
            ?PRINT_MSG("Ignore.~n");
        {error, Error} ->
            ?PRINT("Failed to remove the node from cluster: ~p~n", [Error])
    end;

cluster(["status"]) ->
    ?PRINT("Cluster status: ~p~n", [ekka_cluster:status()]);

cluster(_) ->
    emqx_cli:usage([{"cluster join <Node>",       "Join the cluster"},
                    {"cluster leave",             "Leave the cluster"},
                    {"cluster force-leave <Node>","Force the node leave from cluster"},
                    {"cluster status",            "Cluster status"}]).

%%--------------------------------------------------------------------
%% @doc Users usage

% users(Args) -> emqx_auth_username:cli(Args).

acl(["reload"]) ->
    emqx_access_control:reload_acl();
acl(_) ->
    emqx_cli:usage([{"acl reload", "reload etc/acl.conf"}]).

%%--------------------------------------------------------------------
%% @doc Query clients

clients(["list"]) ->
    dump(emqx_conn);

clients(["show", ClientId]) ->
    if_client(ClientId, fun print/1);

clients(["kick", ClientId]) ->
    if_client(ClientId, fun({_, {_ClientId, Pid}}) -> emqx_connection:kick(Pid) end);

clients(_) ->
    emqx_cli:usage([{"clients list",            "List all clients"},
                    {"clients show <ClientId>", "Show a client"},
                    {"clients kick <ClientId>", "Kick out a client"}]).

if_client(ClientId, Fun) ->
    case ets:lookup(emqx_conn, (bin(ClientId))) of
        [] -> ?PRINT_MSG("Not Found.~n");
        [Client]    -> Fun({emqx_conn, Client})
    end.

%%--------------------------------------------------------------------
%% @doc Sessions Command

sessions(["list"]) ->
    dump(emqx_session);

%% performance issue?

sessions(["list", "persistent"]) ->
    lists:foreach(fun print/1, ets:match_object(emqx_session, {'_', '_', false, '_'}));

%% performance issue?

sessions(["list", "transient"]) ->
    lists:foreach(fun print/1, ets:match_object(emqx_session, {'_', '_', true, '_'}));

sessions(["show", ClientId]) ->
    case ets:lookup(emqx_session, bin(ClientId)) of
        []         -> ?PRINT_MSG("Not Found.~n");
        [SessInfo] -> print({emqx_session, SessInfo})
    end;

sessions(_) ->
    emqx_cli:usage([{"sessions list",            "List all sessions"},
                    {"sessions list persistent", "List all persistent sessions"},
                    {"sessions list transient",  "List all transient sessions"},
                    {"sessions show <ClientId>", "Show a session"}]).

%%--------------------------------------------------------------------
%% @doc Routes Command

routes(["list"]) ->
    dump(emqx_route);

routes(["show", Topic]) ->
    Routes = ets:lookup(emqx_route, bin(Topic)),
    foreach(fun print/1, [{emqx_route, Route} || Route <- Routes]);

routes(_) ->
    emqx_cli:usage([{"routes list",         "List all routes"},
                    {"routes show <Topic>", "Show a route"}]).

subscriptions(["list"]) ->
    lists:foreach(fun(Suboption) ->
                        print({emqx_suboption, Suboption})
                  end, ets:tab2list(emqx_suboption));

subscriptions(["show", ClientId]) ->
    case ets:match_object(emqx_suboption, {{'_', {'_', bin(ClientId)}}, '_'}) of
        [] -> ?PRINT_MSG("Not Found.~n");
        Suboption ->
            [print({emqx_suboption, Sub}) || Sub <- Suboption]
    end;

subscriptions(["add", ClientId, Topic, QoS]) ->
   if_valid_qos(QoS, fun(IntQos) ->
                        case emqx_sm:lookup_session_pid(bin(ClientId)) of
                            Pid when is_pid(Pid) ->
                                {Topic1, Options} = emqx_topic:parse(bin(Topic)),
                                emqx_session:subscribe(Pid, [{Topic1, Options#{qos => IntQos}}]),
                                ?PRINT_MSG("ok~n");
                            _ ->
                                ?PRINT_MSG("Error: Session not found!")
                        end
                     end);

subscriptions(["del", ClientId, Topic]) ->
    case emqx_sm:lookup_session_pid(bin(ClientId)) of
        Pid when is_pid(Pid) ->
            emqx_session:unsubscribe(Pid, [emqx_topic:parse(bin(Topic))]),
            ?PRINT_MSG("ok~n");
        undefined ->
            ?PRINT_MSG("Error: Session not found!")
    end;

subscriptions(_) ->
    emqx_cli:usage([{"subscriptions list",                         "List all subscriptions"},
                    {"subscriptions show <ClientId>",              "Show subscriptions of a client"},
                    {"subscriptions add <ClientId> <Topic> <QoS>", "Add a static subscription manually"},
                    {"subscriptions del <ClientId> <Topic>",       "Delete a static subscription manually"}]).

%if_could_print(Tab, Fun) ->
%    case mnesia:table_info(Tab, size) of
%        Size when Size >= ?MAX_LIMIT ->
%            ?PRINT("Could not list, too many ~ss: ~p~n", [Tab, Size]);
%        _Size ->
%            Keys = mnesia:dirty_all_keys(Tab),
%            foreach(fun(Key) -> Fun(ets:lookup(Tab, Key)) end, Keys)
%    end.

if_valid_qos(QoS, Fun) ->
    try list_to_integer(QoS) of
        Int when ?IS_QOS(Int) -> Fun(Int);
        _ -> ?PRINT_MSG("QoS should be 0, 1, 2~n")
    catch _:_ ->
        ?PRINT_MSG("QoS should be 0, 1, 2~n")
    end.

plugins(["list"]) ->
    foreach(fun print/1, emqx_plugins:list());

plugins(["load", Name]) ->
    case emqx_plugins:load(list_to_atom(Name)) of
        {ok, StartedApps} ->
            ?PRINT("Start apps: ~p~nPlugin ~s loaded successfully.~n", [StartedApps, Name]);
        {error, Reason}   ->
            ?PRINT("load plugin error: ~p~n", [Reason])
    end;

plugins(["unload", Name]) ->
    case emqx_plugins:unload(list_to_atom(Name)) of
        ok ->
            ?PRINT("Plugin ~s unloaded successfully.~n", [Name]);
        {error, Reason} ->
            ?PRINT("unload plugin error: ~p~n", [Reason])
    end;

% plugins(["add", Name]) ->
%     {ok, Path} = emqx:env(expand_plugins_dir),
%     Dir = Path ++ Name,
%     zip:unzip(Dir, [{cwd, Path}]),
%     Plugin = filename:basename(Dir, ".zip"),
%     case emqx_plugins:load_expand_plugin(Path ++ Plugin) of
%         ok ->
%             emqx_cli:print("Add plugin:~p successfully.~n", [Plugin]);
%         {error, {already_loaded,_}} ->
%             emqx_cli:print("Already loaded plugin:~p ~n", [Plugin]);
%         {error, Error} ->
%             emqx_cli:print("Add plugin:~p error: ~n", [Plugin, Error])
%     end;

plugins(_) ->
    emqx_cli:usage([{"plugins list",            "Show loaded plugins"},
                    {"plugins load <Plugin>",   "Load plugin"},
                    {"plugins unload <Plugin>", "Unload plugin"}
                    % {"plugins add <Plugin.zip>", "Add plugin"}
                    ]).

%%--------------------------------------------------------------------
%% @doc Bridges command

% bridges(["list"]) ->
%     foreach(fun({Node, Topic, _Pid}) ->
%                 emqx_cli:print("bridge: ~s--~s-->~s~n", [node(), Topic, Node])
%             end, emqx_bridge_sup_sup:bridges());

% bridges(["options"]) ->
%     ?PRINT_MSG("Options:~n"),
%     ?PRINT_MSG("  qos     = 0 | 1 | 2~n"),
%     ?PRINT_MSG("  prefix  = string~n"),
%     ?PRINT_MSG("  suffix  = string~n"),
%     ?PRINT_MSG("  queue   = integer~n"),
%     ?PRINT_MSG("Example:~n"),
%     ?PRINT_MSG("  qos=2,prefix=abc/,suffix=/yxz,queue=1000~n");

% bridges(["start", SNode, Topic]) ->
%     case emqx_bridge_sup_sup:start_bridge(list_to_atom(SNode), list_to_binary(Topic)) of
%         {ok, _}        -> ?PRINT_MSG("bridge is started.~n");
%         {error, Error} -> ?PRINT("error: ~p~n", [Error])
%     end;

% bridges(["start", SNode, Topic, OptStr]) ->
%     Opts = parse_opts(bridge, OptStr),
%     case emqx_bridge_sup_sup:start_bridge(list_to_atom(SNode), list_to_binary(Topic), Opts) of
%         {ok, _}        -> ?PRINT_MSG("bridge is started.~n");
%         {error, Error} -> ?PRINT("error: ~p~n", [Error])
%     end;

% bridges(["stop", SNode, Topic]) ->
%     case emqx_bridge_sup_sup:stop_bridge(list_to_atom(SNode), list_to_binary(Topic)) of
%         ok             -> ?PRINT_MSG("bridge is stopped.~n");
%         {error, Error} -> ?PRINT("error: ~p~n", [Error])
%     end;

% bridges(_) ->
%     emqx_cli:usage([{"bridges list",                 "List bridges"},
%                     {"bridges options",              "Bridge options"},
%                     {"bridges start <Node> <Topic>", "Start a bridge"},
%                     {"bridges start <Node> <Topic> <Options>", "Start a bridge with options"},
%                     {"bridges stop <Node> <Topic>", "Stop a bridge"}]).

% parse_opts(Cmd, OptStr) ->
%     Tokens = string:tokens(OptStr, ","),
%     [parse_opt(Cmd, list_to_atom(Opt), Val)
%         || [Opt, Val] <- [string:tokens(S, "=") || S <- Tokens]].
% parse_opt(bridge, qos, Qos) ->
%     {qos, list_to_integer(Qos)};
% parse_opt(bridge, suffix, Suffix) ->
%     {topic_suffix, bin(Suffix)};
% parse_opt(bridge, prefix, Prefix) ->
%     {topic_prefix, bin(Prefix)};
% parse_opt(bridge, queue, Len) ->
%     {max_queue_len, list_to_integer(Len)};
% parse_opt(_Cmd, Opt, _Val) ->
%     ?PRINT("Bad Option: ~s~n", [Opt]).

bridges(["list"]) ->
    foreach(fun({Name, State}) ->
                ?PRINT("name: ~s     status: ~s~n", [Name, maps:get(status, State)])
            end, emqx_bridge_sup:bridges());

bridges(["start", Name]) ->
    ?PRINT("~s.~n", [maps:get(msg, emqx_bridge:start_bridge(list_to_atom(Name)))]);

bridges(["stop", Name]) ->
    ?PRINT("~s.~n", [maps:get(msg, emqx_bridge:stop_bridge(list_to_atom(Name)))]);

bridges(["forwards", Name]) ->
    foreach(fun(Topic) ->
        ?PRINT("topic:   ~s~n", [Topic])
    end, emqx_bridge:show_forwards(list_to_atom(Name)));

bridges(["add-forward", Name, Topic]) ->
    case emqx_bridge:add_forward(list_to_atom(Name), iolist_to_binary(Topic)) of
        ok -> ?PRINT_MSG("Add-forward topic successfully.~n");
        {error, Reason} -> ?PRINT("Add-forward failed reason: ~p.~n", [Reason])
    end;

bridges(["del-forward", Name, Topic]) ->
    case emqx_bridge:del_forward(list_to_atom(Name), iolist_to_binary(Topic)) of
        ok -> ?PRINT_MSG("Del-forward topic successfully.~n");
        {error, Reason} -> ?PRINT("Del-forward failed reason: ~p.~n", [Reason])
    end;

bridges(["subscriptions", Name]) ->
    foreach(fun({Topic, Qos}) ->
        ?PRINT("topic: ~s, qos: ~p~n", [Topic, Qos])
    end, emqx_bridge:show_subscriptions(list_to_atom(Name)));

bridges(["add-subscription", Name, Topic, Qos]) ->
    case emqx_bridge:add_subscription(list_to_atom(Name), iolist_to_binary(Topic), list_to_integer(Qos)) of
        ok -> ?PRINT_MSG("Add-subscription topic successfully.~n");
        {error, Reason} -> ?PRINT("Add-subscription failed reason: ~p.~n", [Reason])
    end;

bridges(["del-subscription", Name, Topic]) ->
    case emqx_bridge:del_subscription(list_to_atom(Name), iolist_to_binary(Topic)) of
        ok -> ?PRINT_MSG("Del-subscription topic successfully.~n");
        {error, Reason} -> ?PRINT("Del-subscription failed reason: ~p.~n", [Reason])
    end;

bridges(_) ->
    emqx_cli:usage([{"bridges list",           "List bridges"},
                    {"bridges start <Name>",   "Start a bridge"},
                    {"bridges stop <Name>",    "Stop a bridge"},
                    {"bridges forwards <Name>", "Show a bridge forward topic"},
                    {"bridges add-forward <Name> <Topic>", "Add bridge forward topic"},
                    {"bridges del-forward <Name> <Topic>", "Delete bridge forward topic"},
                    {"bridges subscriptions <Name>", "Show a bridge subscriptions topic"},
                    {"bridges add-subscription <Name> <Topic> <Qos>", "Add bridge subscriptions topic"},
                    {"bridges del-subscription <Name> <Topic>", "Delete bridge subscriptions topic"}]).

%%--------------------------------------------------------------------
%% @doc vm command

vm([]) ->
    vm(["all"]);

vm(["all"]) ->
    [vm([Name]) || Name <- ["load", "memory", "process", "io", "ports"]];

vm(["load"]) ->
    [?PRINT("cpu/~-20s: ~s~n", [L, V]) || {L, V} <- emqx_vm:loads()];

vm(["memory"]) ->
    [?PRINT("memory/~-17s: ~w~n", [Cat, Val]) || {Cat, Val} <- erlang:memory()];

vm(["process"]) ->
    foreach(fun({Name, Key}) ->
                ?PRINT("process/~-16s: ~w~n", [Name, erlang:system_info(Key)])
            end, [{limit, process_limit}, {count, process_count}]);

vm(["io"]) ->
    IoInfo = erlang:system_info(check_io),
    foreach(fun(Key) ->
                ?PRINT("io/~-21s: ~w~n", [Key, get_value(Key, IoInfo)])
            end, [max_fds, active_fds]);

vm(["ports"]) ->
    foreach(fun({Name, Key}) ->
                ?PRINT("ports/~-16s: ~w~n", [Name, erlang:system_info(Key)])
            end, [{count, port_count}, {limit, port_limit}]);

vm(_) ->
    emqx_cli:usage([{"vm all",     "Show info of Erlang VM"},
                    {"vm load",    "Show load of Erlang VM"},
                    {"vm memory",  "Show memory of Erlang VM"},
                    {"vm process", "Show process of Erlang VM"},
                    {"vm io",      "Show IO of Erlang VM"},
                    {"vm ports",   "Show Ports of Erlang VM"}]).

%%--------------------------------------------------------------------
%% @doc mnesia Command

mnesia([]) ->
    mnesia:system_info();

mnesia(_) ->
    ?PRINT_CMD("mnesia", "Mnesia system info").

%%--------------------------------------------------------------------
%% @doc Logger Command

log(["primary-level"]) ->
    Level = emqx_logger:get_primary_log_level(),
   ?PRINT("~s~n", [Level]);

log(["primary-level", Level]) ->
    emqx_logger:set_primary_log_level(list_to_atom(Level)),
    ?PRINT("~s~n", [emqx_logger:get_primary_log_level()]);

log(["handlers", "list"]) ->
    [?PRINT("LogHandler(id=~s, level=~s, destination=~s)~n", [Id, Level, Dst])
        || {Id, Level, Dst} <- emqx_logger:get_log_handlers()];

log(["handlers", "set-level", HandlerId, Level]) ->
    case emqx_logger:set_log_handler_level(list_to_atom(HandlerId), list_to_atom(Level)) of
        ok ->
            {_Id, NewLevel, _Dst} = emqx_logger:get_log_handler(list_to_atom(HandlerId)),
            ?PRINT("~s~n", [NewLevel]);
        {error, Error} ->
            ?PRINT("[error] ~p~n", [Error])
    end;

log(_) ->
    emqx_cli:usage([{"log primary-level", "Show the primary log level now"},
                    {"log primary-level <Level>","Set the primary log level"},
                    {"log handlers list", "Show log handlers"},
                    {"log handlers set-level <HandlerId> <Level>", "Set log level of a log handler"}]).
%%--------------------------------------------------------------------
%% @doc Trace Command

trace(["list"]) ->
    foreach(fun({{Who, Name}, {Level, LogFile}}) ->
                ?PRINT("Trace(~s=~s, level=~s, destination=~p)~n", [Who, Name, Level, LogFile])
            end, emqx_tracer:lookup_traces());

trace(["stop", "client", ClientId]) ->
    trace_off(client_id, ClientId);

trace(["start", "client", ClientId, LogFile]) ->
    trace_on(client_id, ClientId, all, LogFile);

trace(["start", "client", ClientId, LogFile, Level]) ->
    trace_on(client_id, ClientId, list_to_atom(Level), LogFile);

trace(["stop", "topic", Topic]) ->
    trace_off(topic, Topic);

trace(["start", "topic", Topic, LogFile]) ->
    trace_on(topic, Topic, all, LogFile);

trace(["start", "topic", Topic, LogFile, Level]) ->
    trace_on(topic, Topic, list_to_atom(Level), LogFile);

trace(_) ->
    emqx_cli:usage([{"trace list", "List all traces started"},
                    {"trace start client <ClientId> <File> [<Level>]", "Traces for a client"},
                    {"trace stop  client <ClientId>", "Stop tracing for a client"},
                    {"trace start topic  <Topic>    <File> [<Level>] ", "Traces for a topic"},
                    {"trace stop  topic  <Topic> ", "Stop tracing for a topic"}]).

trace_on(Who, Name, Level, LogFile) ->
    case emqx_tracer:start_trace({Who, iolist_to_binary(Name)}, Level, LogFile) of
        ok ->
            ?PRINT("trace ~s ~s successfully~n", [Who, Name]);
        {error, Error} ->
            ?PRINT("[error] trace ~s ~s: ~p~n", [Who, Name, Error])
    end.

trace_off(Who, Name) ->
    case emqx_tracer:stop_trace({Who, iolist_to_binary(Name)}) of
        ok ->
            ?PRINT("stop tracing ~s ~s successfully~n", [Who, Name]);
        {error, Error} ->
            ?PRINT("[error] stop tracing ~s ~s: ~p~n", [Who, Name, Error])
    end.

%%--------------------------------------------------------------------
%% @doc Listeners Command

listeners([]) ->
    foreach(fun({{Protocol, ListenOn}, Pid}) ->
                Info = [{acceptors,      esockd:get_acceptors(Pid)},
                        {max_conns,      esockd:get_max_connections(Pid)},
                        {current_conn,   esockd:get_current_connections(Pid)},
                        {shutdown_count, esockd:get_shutdown_count(Pid)}],
                    ?PRINT("listener on ~s:~s~n", [Protocol, esockd:to_string(ListenOn)]),
                foreach(fun({Key, Val}) ->
                            ?PRINT("  ~-16s: ~w~n", [Key, Val])
                        end, Info)
            end, esockd:listeners()),
    foreach(fun({Protocol, Opts}) ->
                Info = [{acceptors,      proplists:get_value(num_acceptors, Opts)},
                        {max_conns,      proplists:get_value(max_connections, Opts)},
                        {current_conn,   proplists:get_value(all_connections, Opts)},
                        {shutdown_count, []}],
                    ?PRINT("listener on ~s:~p~n", [Protocol, proplists:get_value(port, Opts)]),
                foreach(fun({Key, Val}) ->
                            ?PRINT("  ~-16s: ~w~n", [Key, Val])
                        end, Info)
            end, ranch:info());

% listeners(["restart", Proto, ListenOn]) ->
%     ListenOn1 = case string:tokens(ListenOn, ":") of
%         [Port]     -> list_to_integer(Port);
%         [IP, Port] -> {IP, list_to_integer(Port)}
%     end,
%     case emqx_listeners:restart_listener({list_to_atom(Proto), ListenOn1, []}) of
%         ok ->
%             io:format("Restart ~s listener on ~s successfully.~n", [Proto, ListenOn]);
%         {error, Error} ->
%             io:format("Failed to restart ~s listener on ~s, error:~p~n", [Proto, ListenOn, Error])
%     end;

listeners(["stop",  Name = "http" ++ _N, ListenOn]) ->
    case minirest:stop_http(list_to_atom(Name)) of
        ok ->
            io:format("Stop ~s listener on ~s successfully.~n", [Name, ListenOn]);
        {error, Error} ->
            io:format("Failed to stop ~s listener on ~s, error:~p~n", [Name, ListenOn, Error])
    end;

listeners(["stop", Proto, ListenOn]) ->
    ListenOn1 = case string:tokens(ListenOn, ":") of
        [Port]     -> list_to_integer(Port);
        [IP, Port] -> {IP, list_to_integer(Port)}
    end,
    case emqx_listeners:stop_listener({list_to_atom(Proto), ListenOn1, []}) of
        ok ->
            io:format("Stop ~s listener on ~s successfully.~n", [Proto, ListenOn]);
        {error, Error} ->
            io:format("Failed to stop ~s listener on ~s, error:~p~n", [Proto, ListenOn, Error])
    end;

listeners(_) ->
    emqx_cli:usage([{"listeners",                        "List listeners"},
                    % {"listeners restart <Proto> <Port>", "Restart a listener"},
                    {"listeners stop    <Proto> <Port>", "Stop a listener"}]).

%%--------------------------------------------------------------------
%% @doc License Command

% license(["reload", File]) ->
%     case emqx_license:reload(File) of
%         ok              -> emqx_cli:print("ok~n");
%         {error, Reason} -> emqx_cli:print("Error: ~p~n", [Reason])
%     end;

% license(["info"]) ->
%     foreach(fun({K, V}) when is_binary(V); is_atom(V) ->
%                 emqx_cli:print("~-12s: ~s~n", [K, V]);
%                ({K, V}) ->
%                 emqx_cli:print("~-12s: ~w~n", [K, V])
%             end, emqx_license:info());

% license(_) ->
%     emqx_cli:usage([{"license info",          "Show license info"},
%                     {"license reload <File>", "Load a new license file"}]).

%%--------------------------------------------------------------------
%% Dump ETS
%%--------------------------------------------------------------------

dump(Table) ->
    dump(Table, ets:first(Table)).

dump(_Table, '$end_of_table') ->
    ok;

dump(Table, Key) ->
    case ets:lookup(Table, Key) of
        [Record] -> print({Table, Record});
        [] -> ok
    end,
    dump(Table, ets:next(Table, Key)).

print({_, []}) ->
    ok;

print({emqx_conn, Key}) ->
    [{_, Attrs}] = ets:lookup(emqx_conn_attrs, Key),
    InfoKeys = [client_id,
                clean_start,
                username,
                peername,
                connected_at],
        ?PRINT("Connection(~s, clean_sess=~s, username=~s, peername=~s, connected_at=~p)~n",
           [format(K, get_value(K, Attrs)) || K <- InfoKeys]);

print({emqx_session, Key}) ->
    [{_, Attrs}] = ets:lookup(emqx_session_attrs, Key),
    [{_, Stats}] = ets:lookup(emqx_session_stats, Key),
    InfoKeys = [client_id,
                clean_start,
                subscriptions,
                max_inflight,
                inflight_len,
                mqueue_len,
                mqueue_dropped,
                awaiting_rel_len,
                deliver_msg,
                enqueue_msg,
                created_at],
    ?PRINT("Session(~s, clean_sess=~s, subscriptions=~w, max_inflight=~w, inflight=~w, "
           "mqueue_len=~w, mqueue_dropped=~w, awaiting_rel=~w, "
           "deliver_msg=~w, enqueue_msg=~w, created_at=~w)~n",
            [format(K, get_value(K, Attrs++Stats)) || K <- InfoKeys]);

print({emqx_route, #route{topic = Topic, dest = {_, Node}}}) ->
    ?PRINT("~s -> ~s~n", [Topic, Node]);
print({emqx_route, #route{topic = Topic, dest = Node}}) ->
    ?PRINT("~s -> ~s~n", [Topic, Node]);

print(#plugin{name = Name, version = Ver, descr = Descr, active = Active}) ->
   ?PRINT("Plugin(~s, version=~s, description=~s, active=~s)~n",
           [Name, Ver, Descr, Active]);

print({emqx_suboption, {{Topic, {Sub, ClientId}}, _Options}}) when is_pid(Sub) ->
    ?PRINT("~s -> ~s~n", [ClientId, Topic]).

format(_, undefined) ->
    undefined;

format(CreatedAt, Val) when CreatedAt =:= created_at;
                            CreatedAt =:= connected_at ->
    emqx_time:now_secs(Val);

format(peername, {IPAddr, Port}) ->
    IPStr = emqx_mgmt_util:ntoa(IPAddr),
    io_lib:format("~s:~p", [IPStr, Port]);

format(_, Val) ->
    Val.

bin(S) -> iolist_to_binary(S).