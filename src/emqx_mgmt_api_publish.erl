-module(emqx_mgmt_api_publish).

-export([post/3]).

-export([ validate_encoding/1
        , validate_qos/1
        ]).

-import(emqx_mgmt_api, [rpc_call/3]).

-import(minirest_req, [serialize/2]).

-define(ALLOWED_METHODS, [<<"POST">>]).

-http_api(#{resource => "/publish",
            allowed_methods => ?ALLOWED_METHODS,
            private => false,
            post => #{body => [{<<"clientid">>,                          [nonempty]},
                               {<<"topic">>,                             [fun emqx_mgmt_api:validate_topic_name/1]},
                               {<<"payload">>,                           [nonempty]},
                               {<<"encoding">>, {optional, <<"plain">>}, [fun ?MODULE:validate_encoding/1]},
                               {<<"qos">>, {optional, 0},                [int, fun ?MODULE:validate_qos/1]},
                               {<<"retain">>, {optional, false},         [bool]}]}}).

post(_, _, Body) ->
    publish(Body),
    204.

publish(Message) when is_map(Message) ->
    publish([Message]);
publish([]) ->
    ok;
publish([#{<<"clientid">> := ClientId,
           <<"topic">>    := Topic,
           <<"payload">>  := Payload,
           <<"encoding">> := Encoding,
           <<"qos">>      := QoS,
           <<"retain">>   := Retain} | More]) ->
    Msg = emqx_message:make(ClientId, QoS, Topic, decode_payload(Payload, Encoding)),
    emqx:publish(emqx_message:set_flag(retain, Retain, Msg)),
    publish(More).

validate_encoding(Encoding) ->
    case minirest:within(Encoding, [<<"plain">>, <<"base64">>]) of
        true -> ok;
        false -> {error, not_valid_encoding}
    end.

validate_qos(0) ->
    ok;
validate_qos(1) ->
    ok;
validate_qos(2) ->
    ok;
validate_qos(_) ->
    {error, not_valid_qos}.

decode_payload(Payload, <<"base64">>) -> base64:decode(Payload);
decode_payload(Payload, <<"plain">>) -> Payload.