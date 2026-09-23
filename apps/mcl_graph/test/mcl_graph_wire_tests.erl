%% @doc What a reply or a fact looks like to a caller that is not on the BEAM.
%%
%% A bare Erlang binary goes out as a CBOR BYTE string, and macula-cli,
%% macula-mcp and every non-BEAM SDK render that as `0x...' hex. Every string
%% this service sends is human-readable (entity ids, predicates, prose, the
%% link id's hex), so every one of them must leave as `{text, Bin}'. A
%% BEAM-to-BEAM call never shows the difference, which is why it is asserted
%% here rather than noticed later.
-module(mcl_graph_wire_tests).

-include_lib("eunit/include/eunit.hrl").

a_binary_leaves_as_text_test() ->
    ?assertEqual({text, <<"did:macula:alice">>}, mcl_graph_wire:to_wire(<<"did:macula:alice">>)).

numbers_leave_as_they_are_test() ->
    ?assertEqual(42, mcl_graph_wire:to_wire(42)),
    ?assertEqual(0.85, mcl_graph_wire:to_wire(0.85)).

%% No booleans on the wire: a JSON true/false out of CozoDB leaves as 1/0.
booleans_leave_as_one_and_zero_test() ->
    ?assertEqual(1, mcl_graph_wire:to_wire(true)),
    ?assertEqual(0, mcl_graph_wire:to_wire(false)).

%% CozoDB's JSON null reaches Erlang as `nil'; it leaves as null, not as the
%% text "nil".
json_null_leaves_as_null_test() ->
    ?assertEqual(undefined, mcl_graph_wire:to_wire(nil)).

maps_and_lists_are_tagged_all_the_way_down_test() ->
    Row = #{<<"predicate">> => <<"knows">>, <<"hop">> => 2,
            <<"attrs">> => #{<<"tags">> => [<<"a">>, <<"b">>]}},
    ?assertEqual(#{<<"predicate">> => {text, <<"knows">>}, <<"hop">> => 2,
                   <<"attrs">> => #{<<"tags">> => [{text, <<"a">>}, {text, <<"b">>}]}},
                 mcl_graph_wire:to_wire(Row)).

already_tagged_text_is_left_alone_test() ->
    ?assertEqual({text, <<"x">>}, mcl_graph_wire:to_wire({text, <<"x">>})).

%% The property that matters: nothing a caller receives is a bare binary.
no_bare_binary_survives_test() ->
    Reply = #{rows => [#{<<"entity">> => <<"did:macula:bob">>, <<"hop">> => 1}],
              link_id => <<"0123456789abcdef">>, prose => <<"Alice knows Bob.">>},
    ?assertEqual([], bare_binaries(mcl_graph_wire:to_wire(Reply))).

%% Whatever it sends, macula can send.
every_reply_passes_macula_s_payload_check_test() ->
    Reply = #{rows => [#{<<"entity">> => <<"did:macula:bob">>, <<"confidence">> => 0.9,
                         <<"flag">> => true, <<"gone">> => nil}]},
    ?assertEqual(ok, macula_frame:check_payload(mcl_graph_wire:to_wire(Reply))).

bare_binaries(B) when is_binary(B) -> [B];
bare_binaries({text, _}) -> [];
bare_binaries(L) when is_list(L) -> lists:append([bare_binaries(E) || E <- L]);
bare_binaries(M) when is_map(M) -> bare_binaries(maps:values(M));
bare_binaries(_) -> [].
