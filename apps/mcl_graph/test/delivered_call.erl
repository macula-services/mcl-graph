%% @doc A payload exactly as a desk receives it from a real macula 12 CALL.
%%
%% The CALL is built and signed by `Caller', encoded, decoded and verified by
%% macula's own codec, and the wire-authenticated caller merged in the way
%% macula_station_link does before a handler runs. A test that hands a desk a
%% hand-written map proves the desk reads hand-written maps: text arrives
%% `{text, Bin}', keys of nested maps included, and nothing but this shows it.
-module(delivered_call).

-export([node_key/0, node_id/1, delivered/2]).

-spec node_key() -> macula_node_keys:node_key().
node_key() ->
    {ok, Key} = macula_node_keys:generate(identity, profile(), #{puzzle_difficulty => 0}),
    Key.

-spec node_id(macula_node_keys:node_key()) -> binary().
node_id(Key) ->
    {ok, Id} = macula_node_keys:node_id(Key),
    Id.

%% @doc `Payload' as the handler of a CALL from `Caller' would receive it.
-spec delivered(map(), macula_node_keys:node_key()) -> map().
delivered(Payload, Caller) ->
    Spec = #{request_id => crypto:strong_rand_bytes(16),
             realm => crypto:hash(sha256, <<"io.macula">>),
             procedure => <<"mcl-graph/learn_link">>,
             target => node_id(node_key()),
             deadline => erlang:system_time(millisecond) + 60_000,
             payload => Payload},
    Frame = macula_frame:call(Spec, Caller),
    {ok, Decoded, <<>>} = macula_frame:decode(macula_frame:encode(Frame)),
    {ok, #{payload := Delivered, caller := CallerId}} =
        macula_frame:verify_request(Decoded, profile()),
    Delivered#{caller => CallerId}.

profile() ->
    {ok, P} = macula_crypto_profile:configured(),
    P.
