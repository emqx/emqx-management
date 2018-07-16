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

-import(lists, [foreach/2]).

-import(proplists, [get_value/2]).

-export([load/0]).

-export([status/1, broker/1, cluster/1, users/1, clients/1, sessions/1,
         routes/1, topics/1, subscriptions/1, plugins/1, bridges/1,
         listeners/1, vm/1, mnesia/1, trace/1, acl/1, license/1, mgmt/1, configs/1]).

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
    lists:foreach(fun(Cmd) -> emqx_ctl:register_cmd(Cmd, {?MODULE, Cmd}, []) end, Cmds),
    emqx_mgmt_cli_cfg:register_config().

is_cmd(Fun) ->
    not lists:member(Fun, [init, load, module_info]).
mgmt(["add_app", AppId, Name, Desc, Status]) ->
    mgmt(["add_app", AppId, Name, Desc, Status, undefined]);

mgmt(["add_app", AppId, Name, Desc, Status, Expired]) ->
    Expired1 = case Expired of
        undefined -> undefined;
        _ -> list_to_integer(Expired)
    end,
    case emqx_mgmt_auth:add_app(list_to_binary(AppId),
                                list_to_binary(Name),
                                list_to_binary(Desc),
                                list_to_atom(Status),
                                Expired1) of
        {ok, Secret} ->
            emqx_cli:print("AppSecret: ~s~n", [Secret]);
        {error, already_existed} ->
            emqx_cli:print("Error: already existed~n");
        {error, Reason} ->
            emqx_cli:print("Error: ~p~n", [Reason])
    end;

mgmt(["lookup_app", AppId]) ->
    case emqx_mgmt_auth:lookup_app(list_to_binary(AppId)) of
        {AppId1, AppSecret, Name, Desc, Status, Expired} ->
            emqx_cli:print("app_id: ~s~nsecret: ~s~nname: ~s~ndesc: ~s~nstatus: ~s~nexpired: ~p~n",
                           [AppId1, AppSecret, Name, Desc, Status, Expired]);
        undefined ->
            emqx_cli:print("Not Found.~n")
    end;

mgmt(["update_app", AppId, Name, Desc, Status, Expired]) ->
    case emqx_mgmt_auth:update_app(list_to_binary(AppId),
                                   list_to_binary(Name),
                                   list_to_binary(Desc),
                                   list_to_atom(Status),
                                   list_to_integer(Expired)) of
        ok ->
            emqx_cli:print("update successfully.~n");
        {error, Reason} ->
            emqx_cli:print("Error: ~p~n", [Reason])
    end;

mgmt(["del_app", AppId]) ->
    case emqx_mgmt_auth:del_app(list_to_binary(AppId)) of
        ok -> emqx_cli:print("ok~n");
        {error, not_found} ->
            emqx_cli:print("Error: app not found~n");
        {error, Reason} ->
            emqx_cli:print("Error: ~p~n", [Reason])
    end;

mgmt(["list_apps"]) ->
    lists:foreach(fun({AppId, AppSecret, Name, Desc, Status, Expired}) ->
        emqx_cli:print("app_id: ~s, secret: ~s, name: ~s, desc: ~s, status: ~s, expired: ~p~n",
                       [AppId, AppSecret, Name, Desc, Status, Expired])
    end, emqx_mgmt_auth:list_apps());

mgmt(_) ->
    emqx_cli:usage([{"mgmt add_app <AppId> <Name> <Desc> <status> <expired>", "Add Application of REST API"},
                    {"mgmt lookup_app <AppId>", "Get Application of REST API"},
                    {"mgmt update_app <AppId> <Name> <Desc> <status> <expired>", "Get Application of REST API"},
                    {"mgmt del_app <AppId>", "Delete Application of REST API"},
                    {"mgmt list_apps",       "List Applications"}]).

configs(["set"]) ->
    emqx_mgmt_cli_cfg:set_usage(), ok;

configs(Cmd) when length(Cmd) > 2 ->
    emqx_mgmt_cli_cfg:run(["config" | Cmd]), ok;

configs(_) ->
    emqx_cli:usage([{"configs set",                           "Show All configs Item"},
                    {"configs set <Key>=<Value> --app=<app>", "Set Config Item"},
                    {"configs show <Key> --app=<app>",        "show Config Item"}]).

%%--------------------------------------------------------------------
%% @doc Node status

status([]) ->
    {InternalStatus, _ProvidedStatus} = init:get_status(),
    emqx_cli:print("Node ~p is ~p~n", [node(), InternalStatus]),
    case lists:keysearch(?APP, 1, application:which_applications()) of
        false ->
            emqx_cli:print("~s is not running~n", [?APP]);
        {value, {?APP, _Desc, Vsn}} ->
            emqx_cli:print("~s ~s is running~n", [?APP, Vsn])
    end;
status(_) ->
     emqx_cli:usage("status", "Show broker status").

%%--------------------------------------------------------------------
%% @doc Query broker

broker([]) ->
    Funs = [sysdescr, version, uptime, datetime],
    foreach(fun(Fun) ->
                emqx_cli:usage("~-10s: ~s~n", [Fun, emqx_broker:Fun()])
            end, Funs);

broker(["stats"]) ->
    foreach(fun({Stat, Val}) ->
                emqx_cli:usage("~-20s: ~w~n", [Stat, Val])
            end, emqx_stats:getstats());

broker(["metrics"]) ->
    foreach(fun({Metric, Val}) ->
                emqx_cli:usage("~-24s: ~w~n", [Metric, Val])
            end, lists:sort(emqx_metrics:all()));

broker(["pubsub"]) ->
    Pubsubs = supervisor:which_children(emqx_pubsub_sup:pubsub_pool()),
    foreach(fun({{_, Id}, Pid, _, _}) ->
                ProcInfo = erlang:process_info(Pid, ?PROC_INFOKEYS),
                emqx_cli:usage("pubsub: ~w~n", [Id]),
                foreach(fun({Key, Val}) ->
                            emqx_cli:usage("  ~-18s: ~w~n", [Key, Val])
                        end, ProcInfo)
             end, lists:reverse(Pubsubs));

broker(_) ->
    emqx_cli:usage([{"broker",         "Show broker version, uptime and description"},
                    {"broker pubsub",  "Show process_info of pubsub"},
                    {"broker stats",   "Show broker statistics of clients, topics, subscribers"},
                    {"broker metrics", "Show broker metrics"}]).

%%-----------------------------------------------------------------------------
%% @doc Cluster with other nodes

cluster(["join", SNode]) ->
    case ekka:join(ekka_node:parse_name(SNode)) of
        ok ->
            emqx_cli:print("Join the cluster successfully.~n"),
            cluster(["status"]);
        ignore ->
            emqx_cli:print("Ignore.~n");
        {error, Error} ->
            emqx_cli:print("Failed to join the cluster: ~p~n", [Error])
    end;

cluster(["leave"]) ->
    case ekka:leave() of
        ok ->
            emqx_cli:print("Leave the cluster successfully.~n"),
            cluster(["status"]);
        {error, Error} ->
            emqx_cli:print("Failed to leave the cluster: ~p~n", [Error])
    end;

cluster(["force-leave", SNode]) ->
    case ekka:force_leave(ekka_node:parse_name(SNode)) of
        ok ->
            emqx_cli:print("Remove the node from cluster successfully.~n"),
            cluster(["status"]);
        ignore ->
            emqx_cli:print("Ignore.~n");
        {error, Error} ->
            emqx_cli:print("Failed to remove the node from cluster: ~p~n", [Error])
    end;

cluster(["status"]) ->
    emqx_cli:print("Cluster status: ~p~n", [ekka_cluster:status()]);

cluster(_) ->
    emqx_cli:usage([{"cluster join <Node>",       "Join the cluster"},
                    {"cluster leave",             "Leave the cluster"},
                    {"cluster force-leave <Node>","Force the node leave from cluster"},
                    {"cluster status",            "Cluster status"}]).

%%--------------------------------------------------------------------
%% @doc Users usage

users(Args) -> emqx_auth_username:cli(Args).

acl(["reload"]) ->
    emqx_access_control:reload_acl();
acl(_) ->
    emqx_cli:usage([{"acl reload", "reload etc/acl.conf"}]).

%%--------------------------------------------------------------------
%% @doc Query clients

clients(["list"]) ->
    dump(mqtt_client);

clients(["show", ClientId]) ->
    if_client(ClientId, fun print/1);

clients(["kick", ClientId]) ->
    if_client(ClientId, fun(#mqtt_client{client_pid = Pid}) -> emqx_client:kick(Pid) end);

clients(_) ->
    emqx_cli:usage([{"clients list",            "List all clients"},
                    {"clients show <ClientId>", "Show a client"},
                    {"clients kick <ClientId>", "Kick out a client"}]).

if_client(ClientId, Fun) ->
    case emqx_cm:lookup(bin(ClientId)) of
        undefined -> emqx_cli:print("Not Found.~n");
        Client    -> Fun(Client)
    end.

%%--------------------------------------------------------------------
%% @doc Sessions Command

sessions(["list"]) ->
    dump(mqtt_local_session);

%% performance issue?

sessions(["list", "persistent"]) ->
    lists:foreach(fun print/1, ets:match_object(mqtt_local_session, {'_', '_', false, '_'}));

%% performance issue?

sessions(["list", "transient"]) ->
    lists:foreach(fun print/1, ets:match_object(mqtt_local_session, {'_', '_', true, '_'}));

sessions(["show", ClientId]) ->
    case ets:lookup(mqtt_local_session, bin(ClientId)) of
        []         -> emqx_cli:print("Not Found.~n");
        [SessInfo] -> print(SessInfo)
    end;

sessions(_) ->
    emqx_cli:usage([{"sessions list",            "List all sessions"},
                    {"sessions list persistent", "List all persistent sessions"},
                    {"sessions list transient",  "List all transient sessions"},
                    {"sessions show <ClientId>", "Show a session"}]).

%%--------------------------------------------------------------------
%% @doc Routes Command

routes(["list"]) ->
    Routes = emqx_router:dump(),
    foreach(fun print/1, Routes);

routes(["show", Topic]) ->
    Routes = lists:append(ets:lookup(mqtt_route, bin(Topic)),
                          ets:lookup(mqtt_local_route, bin(Topic))),
    foreach(fun print/1, Routes);

routes(_) ->
    emqx_cli:usage([{"routes list",         "List all routes"},
                    {"routes show <Topic>", "Show a route"}]).

%%--------------------------------------------------------------------
%% @doc Topics Command

topics(["list"]) ->
    lists:foreach(fun(Topic) -> emqx_cli:print("~s~n", [Topic]) end, emqx:topics());

topics(["show", Topic]) ->
    print(mnesia:dirty_read(mqtt_route, bin(Topic)));

topics(_) ->
    emqx_cli:usage([{"topics list",         "List all topics"},
                    {"topics show <Topic>", "Show a topic"}]).

subscriptions(["list"]) ->
    lists:foreach(fun(Subscription) ->
                      print(subscription, Subscription)
                  end, ets:tab2list(mqtt_subscription));

subscriptions(["show", ClientId]) ->
    case emqx:subscriptions(bin(ClientId)) of
        [] -> emqx_cli:print("Not Found.~n");
        Subscriptions ->
            [print(subscription, Sub) || Sub <- Subscriptions]
    end;

subscriptions(["add", ClientId, Topic, QoS]) ->
   if_valid_qos(QoS, fun(IntQos) ->
                        case emqx_sm:lookup_session(bin(ClientId)) of
                            undefined ->
                                emqx_cli:print("Error: Session not found!");
                            #mqtt_session{sess_pid = SessPid} ->
                                {Topic1, Options} = emqx_topic:parse(bin(Topic)),
                                emqx_session:subscribe(SessPid, [{Topic1, [{qos, IntQos}|Options]}]),
                                emqx_cli:print("ok~n")
                        end
                     end);

subscriptions(["del", ClientId, Topic]) ->
    case emqx_sm:lookup_session(bin(ClientId)) of
        undefined ->
            emqx_cli:print("Error: Session not found!");
        #mqtt_session{sess_pid = SessPid} ->
            emqx_session:unsubscribe(SessPid, [emqx_topic:parse(bin(Topic))]),
            emqx_cli:print("ok~n")
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
        _ -> emqx_cli:print("QoS should be 0, 1, 2~n")
    catch _:_ ->
        emqx_cli:print("QoS should be 0, 1, 2~n")
    end.

plugins(["list"]) ->
    foreach(fun print/1, emqx_plugins:list());

plugins(["load", Name]) ->
    case emqx_plugins:load(list_to_atom(Name)) of
        {ok, StartedApps} ->
            emqx_cli:print("Start apps: ~p~nPlugin ~s loaded successfully.~n", [StartedApps, Name]);
        {error, Reason}   ->
            emqx_cli:print("load plugin error: ~p~n", [Reason])
    end;

plugins(["unload", Name]) ->
    case emqx_plugins:unload(list_to_atom(Name)) of
        ok ->
            emqx_cli:print("Plugin ~s unloaded successfully.~n", [Name]);
        {error, Reason} ->
            emqx_cli:print("unload plugin error: ~p~n", [Reason])
    end;

plugins(["add", Name]) ->
    {ok, Path} = emqx:env(expand_plugins_dir),
    Dir = Path ++ Name,
    zip:unzip(Dir, [{cwd, Path}]),
    Plugin = filename:basename(Dir, ".zip"),
    case emqx_plugins:load_expand_plugin(Path ++ Plugin) of
        ok ->
            emqx_cli:print("Add plugin:~p successfully.~n", [Plugin]);
        {error, {already_loaded,_}} ->
            emqx_cli:print("Already loaded plugin:~p ~n", [Plugin]);
        {error, Error} ->
            emqx_cli:print("Add plugin:~p error: ~n", [Plugin, Error])
    end;

plugins(_) ->
    emqx_cli:usage([{"plugins list",            "Show loaded plugins"},
                    {"plugins load <Plugin>",   "Load plugin"},
                    {"plugins unload <Plugin>", "Unload plugin"},
                    {"plugins add <Plugin.zip>", "Add plugin"}]).

%%--------------------------------------------------------------------
%% @doc Bridges command

bridges(["list"]) ->
    foreach(fun({Node, Topic, _Pid}) ->
                emqx_cli:print("bridge: ~s--~s-->~s~n", [node(), Topic, Node])
            end, emqx_bridge_sup_sup:bridges());

bridges(["options"]) ->
    ?PRINT_MSG("Options:~n"),
    ?PRINT_MSG("  qos     = 0 | 1 | 2~n"),
    ?PRINT_MSG("  prefix  = string~n"),
    ?PRINT_MSG("  suffix  = string~n"),
    ?PRINT_MSG("  queue   = integer~n"),
    ?PRINT_MSG("Example:~n"),
    ?PRINT_MSG("  qos=2,prefix=abc/,suffix=/yxz,queue=1000~n");

bridges(["start", SNode, Topic]) ->
    case emqx_bridge_sup_sup:start_bridge(list_to_atom(SNode), list_to_binary(Topic)) of
        {ok, _}        -> ?PRINT_MSG("bridge is started.~n");
        {error, Error} -> ?PRINT("error: ~p~n", [Error])
    end;

bridges(["start", SNode, Topic, OptStr]) ->
    Opts = parse_opts(bridge, OptStr),
    case emqx_bridge_sup_sup:start_bridge(list_to_atom(SNode), list_to_binary(Topic), Opts) of
        {ok, _}        -> ?PRINT_MSG("bridge is started.~n");
        {error, Error} -> ?PRINT("error: ~p~n", [Error])
    end;

bridges(["stop", SNode, Topic]) ->
    case emqx_bridge_sup_sup:stop_bridge(list_to_atom(SNode), list_to_binary(Topic)) of
        ok             -> ?PRINT_MSG("bridge is stopped.~n");
        {error, Error} -> ?PRINT("error: ~p~n", [Error])
    end;

bridges(_) ->
    emqx_cli:usage([{"bridges list",                 "List bridges"},
                    {"bridges options",              "Bridge options"},
                    {"bridges start <Node> <Topic>", "Start a bridge"},
                    {"bridges start <Node> <Topic> <Options>", "Start a bridge with options"},
                    {"bridges stop <Node> <Topic>", "Stop a bridge"}]).

parse_opts(Cmd, OptStr) ->
    Tokens = string:tokens(OptStr, ","),
    [parse_opt(Cmd, list_to_atom(Opt), Val)
        || [Opt, Val] <- [string:tokens(S, "=") || S <- Tokens]].
parse_opt(bridge, qos, Qos) ->
    {qos, list_to_integer(Qos)};
parse_opt(bridge, suffix, Suffix) ->
    {topic_suffix, bin(Suffix)};
parse_opt(bridge, prefix, Prefix) ->
    {topic_prefix, bin(Prefix)};
parse_opt(bridge, queue, Len) ->
    {max_queue_len, list_to_integer(Len)};
parse_opt(_Cmd, Opt, _Val) ->
    ?PRINT("Bad Option: ~s~n", [Opt]).

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
%% @doc Trace Command

trace(["list"]) ->
    foreach(fun({{Who, Name}, LogFile}) ->
                ?PRINT("trace ~s ~s -> ~s~n", [Who, Name, LogFile])
            end, emqx_trace:all_traces());

trace(["client", ClientId, "off"]) ->
    trace_off(client, ClientId);

trace(["client", ClientId, LogFile]) ->
    trace_on(client, ClientId, LogFile);

trace(["topic", Topic, "off"]) ->
    trace_off(topic, Topic);

trace(["topic", Topic, LogFile]) ->
    trace_on(topic, Topic, LogFile);

trace(_) ->
    emqx_cli:usage([{"trace list",                       "List all traces"},
                    {"trace client <ClientId> <LogFile>","Trace a client"},
                    {"trace client <ClientId> off",      "Stop tracing a client"},
                    {"trace topic <Topic> <LogFile>",    "Trace a topic"},
                    {"trace topic <Topic> off",          "Stop tracing a Topic"}]).

trace_on(Who, Name, LogFile) ->
    case emqx_trace:start_trace({Who, iolist_to_binary(Name)}, LogFile) of
        ok ->
            emqx_cli:print("trace ~s ~s successfully.~n", [Who, Name]);
        {error, Error} ->
            emqx_cli:print("trace ~s ~s error: ~p~n", [Who, Name, Error])
    end.

trace_off(Who, Name) ->
    case emqx_trace:stop_trace({Who, iolist_to_binary(Name)}) of
        ok ->
            emqx_cli:print("stop tracing ~s ~s successfully.~n", [Who, Name]);
        {error, Error} ->
            emqx_cli:print("stop tracing ~s ~s error: ~p.~n", [Who, Name, Error])
    end.

%%--------------------------------------------------------------------
%% @doc Listeners Command

listeners([]) ->
    foreach(fun({{Protocol, ListenOn}, Pid}) ->
                Info = [{acceptors,      esockd:get_acceptors(Pid)},
                        {max_clients,    esockd:get_max_clients(Pid)},
                        {current_clients,esockd:get_current_clients(Pid)},
                        {shutdown_count, esockd:get_shutdown_count(Pid)}],
                emqx_cli:print("listener on ~s:~s~n", [Protocol, esockd:to_string(ListenOn)]),
                foreach(fun({Key, Val}) ->
                            emqx_cli:print("  ~-16s: ~w~n", [Key, Val])
                        end, Info)
            end, esockd:listeners());

listeners(["restart", Proto, ListenOn]) ->
    ListenOn1 = case string:tokens(ListenOn, ":") of
        [Port]     -> list_to_integer(Port);
        [IP, Port] -> {IP, list_to_integer(Port)}
    end,
    case emqx:restart_listener({list_to_atom(Proto), ListenOn1, []}) of
        {ok, _Pid} ->
            io:format("Restart ~s listener on ~s successfully.~n", [Proto, ListenOn]);
        {error, Error} ->
            io:format("Failed to restart ~s listener on ~s, error:~p~n", [Proto, ListenOn, Error])
    end;

listeners(["stop", Proto, ListenOn]) ->
    ListenOn1 = case string:tokens(ListenOn, ":") of
        [Port]     -> list_to_integer(Port);
        [IP, Port] -> {IP, list_to_integer(Port)}
    end,
    case emqx:stop_listener({list_to_atom(Proto), ListenOn1, []}) of
        ok ->
            io:format("Stop ~s listener on ~s successfully.~n", [Proto, ListenOn]);
        {error, Error} ->
            io:format("Failed to stop ~s listener on ~s, error:~p~n", [Proto, ListenOn, Error])
    end;

listeners(_) ->
    emqx_cli:usage([{"listeners",                        "List listeners"},
                    {"listeners restart <Proto> <Port>", "Restart a listener"},
                    {"listeners stop    <Proto> <Port>", "Stop a listener"}]).

%%--------------------------------------------------------------------
%% @doc License Command

license(["reload", File]) ->
    case emqx_license:reload(File) of
        ok              -> emqx_cli:print("ok~n");
        {error, Reason} -> emqx_cli:print("Error: ~p~n", [Reason])
    end;

license(["info"]) ->
    foreach(fun({K, V}) when is_binary(V); is_atom(V) ->
                emqx_cli:print("~-12s: ~s~n", [K, V]);
               ({K, V}) ->
                emqx_cli:print("~-12s: ~w~n", [K, V])
            end, emqx_license:info());

license(_) ->
    emqx_cli:usage([{"license info",          "Show license info"},
                    {"license reload <File>", "Load a new license file"}]).

%%--------------------------------------------------------------------
%% Dump ETS
%%--------------------------------------------------------------------

dump(Table) ->
    dump(Table, ets:first(Table)).

dump(_Table, '$end_of_table') ->
    ok;

dump(Table, Key) ->
    case ets:lookup(Table, Key) of
        [Record] -> print(Record);
        [] -> ok
    end,
    dump(Table, ets:next(Table, Key)).

print([]) ->
    ok;

print(Routes = [#mqtt_route{topic = Topic} | _]) ->
    Nodes = [atom_to_list(Node) || #mqtt_route{node = Node} <- Routes],
    emqx_cli:print("~s -> ~s~n", [Topic, string:join(Nodes, ",")]);

%% print(Subscriptions = [#mqtt_subscription{subid = ClientId} | _]) ->
%%    TopicTable = [io_lib:format("~s:~w", [Topic, Qos])
%%                  || #mqtt_subscription{topic = Topic, qos = Qos} <- Subscriptions],
%%    ?PRINT("~s -> ~s~n", [ClientId, string:join(TopicTable, ",")]);

%% print(Topics = [#mqtt_topic{}|_]) ->
%%    foreach(fun print/1, Topics);

print(#mqtt_plugin{name = Name, version = Ver, descr = Descr, active = Active}) ->
    emqx_cli:print("Plugin(~s, version=~s, description=~s, active=~s)~n",
           [Name, Ver, Descr, Active]);

print(#mqtt_client{client_id = ClientId, clean_sess = CleanSess, username = Username,
                   peername = Peername, connected_at = ConnectedAt}) ->
    emqx_cli:print("Client(~s, clean_sess=~s, username=~s, peername=~s, connected_at=~p)~n",
           [ClientId, CleanSess, Username, emqx_net:format(Peername),
            emqx_time:now_secs(ConnectedAt)]);

%% print(#mqtt_topic{topic = Topic, flags = Flags}) ->
%%    ?PRINT("~s: ~s~n", [Topic, string:join([atom_to_list(F) || F <- Flags], ",")]);
print({route, Routes}) ->
    foreach(fun print/1, Routes);
print({local_route, Routes}) ->
    foreach(fun print/1, Routes);
print(#mqtt_route{topic = Topic, node = Node}) ->
    emqx_cli:print("~s -> ~s~n", [Topic, Node]);
print({Topic, Node}) ->
    emqx_cli:print("~s -> ~s~n", [Topic, Node]);

print({ClientId, _ClientPid, _Persistent, SessInfo}) ->
    Data = lists:append(SessInfo, emqx_stats:get_session_stats(ClientId)),
    InfoKeys = [clean_sess,
                subscriptions,
                max_inflight,
                inflight_len,
                mqueue_len,
                mqueue_dropped,
                awaiting_rel_len,
                deliver_msg,
                enqueue_msg,
                created_at],
    emqx_cli:print("Session(~s, clean_sess=~s, subscriptions=~w, max_inflight=~w, inflight=~w, "
           "mqueue_len=~w, mqueue_dropped=~w, awaiting_rel=~w, "
           "deliver_msg=~w, enqueue_msg=~w, created_at=~w)~n",
            [ClientId | [format(Key, get_value(Key, Data)) || Key <- InfoKeys]]).

print(subscription, {Sub, {share, _Share, Topic}}) when is_pid(Sub) ->
    emqx_cli:print("~p -> ~s~n", [Sub, Topic]);
print(subscription, {Sub, Topic}) when is_pid(Sub) ->
    emqx_cli:print("~p -> ~s~n", [Sub, Topic]);
print(subscription, {{SubId, SubPid}, {share, _Share, Topic}})
    when is_binary(SubId), is_pid(SubPid) ->
    emqx_cli:print("~s~p -> ~s~n", [SubId, SubPid, Topic]);
print(subscription, {{SubId, SubPid}, Topic})
    when is_binary(SubId), is_pid(SubPid) ->
    emqx_cli:print("~s~p -> ~s~n", [SubId, SubPid, Topic]);
print(subscription, {Sub, Topic, Props}) ->
    print(subscription, {Sub, Topic}),
    lists:foreach(fun({K, V}) when is_binary(V) ->
                      emqx_cli:print("  ~-8s: ~s~n", [K, V]);
                     ({K, V}) ->
                      emqx_cli:print("  ~-8s: ~w~n", [K, V]);
                     (K) ->
                      emqx_cli:print("  ~-8s: true~n", [K])
                  end, Props).

format(created_at, Val) ->
    emqx_time:now_secs(Val);

format(_, Val) ->
    Val.

bin(S) -> iolist_to_binary(S).
