%% @doc resolve_link: direct, filtered, reverse and N-hop queries.
-module(resolve_link_tests).

-include_lib("eunit/include/eunit.hrl").

resolve_link_test_() ->
    {foreach,
     fun() -> meck:new(mcl_graph_store, [non_strict]) end,
     fun(_) -> meck:unload(mcl_graph_store) end,
     [fun direct_out_rows_are_named/0,
      fun direct_out_filtered_by_predicate/0,
      fun direct_in/0,
      fun direct_both/0,
      fun traversal_returns_every_hop/0,
      fun traversal_in_walks_edges_backwards/0,
      fun an_unknown_direction_is_refused/0,
      fun a_depth_below_one_is_refused/0,
      fun a_depth_above_the_cap_is_refused/0,
      fun both_directions_with_a_predicate/0,
      fun a_store_failure_reaches_the_caller_as_store_error/0,
      fun a_missing_subject_is_refused/0,
      fun a_real_wire_call_resolves/0,
      fun the_reply_is_text_not_bytes/0]}.

direct_out_rows_are_named() ->
    rows([<<"predicate">>, <<"object">>, <<"confidence">>, <<"source">>, <<"learned_at">>],
         [[<<"knows">>, <<"did:macula:bob">>, 1.0, <<"mcl-graph">>, 1788244318000]]),
    {ok, [Row]} = resolve_link:resolve(#{subject => <<"did:macula:alice">>, direction => <<"out">>}),
    ?assertEqual(<<"knows">>, maps:get(<<"predicate">>, Row)),
    ?assertEqual(<<"did:macula:bob">>, maps:get(<<"object">>, Row)).

direct_out_filtered_by_predicate() ->
    rows([<<"object">>, <<"confidence">>, <<"source">>, <<"learned_at">>],
         [[<<"did:macula:bob">>, 0.9, <<"mcl-graph">>, 1788244318000]]),
    {ok, [Row]} = resolve_link:resolve(#{subject => <<"did:macula:alice">>,
                                         predicate => <<"knows">>}),
    ?assertEqual(<<"did:macula:bob">>, maps:get(<<"object">>, Row)),
    [{_Q, Params}] = store_calls(),
    ?assertEqual(<<"knows">>, maps:get(<<"predicate">>, Params)).

direct_in() ->
    rows([<<"subject">>, <<"predicate">>, <<"confidence">>, <<"source">>, <<"learned_at">>],
         [[<<"did:macula:charlie">>, <<"authored">>, 0.8, <<"mcl-graph">>, 1788244318000]]),
    {ok, [Row]} = resolve_link:resolve(#{subject => <<"did:macula:alice">>, direction => <<"in">>}),
    ?assertEqual(<<"did:macula:charlie">>, maps:get(<<"subject">>, Row)).

direct_both() ->
    rows([<<"direction">>, <<"entity">>, <<"predicate">>, <<"confidence">>],
         [[<<"out">>, <<"did:macula:bob">>, <<"knows">>, 1.0],
          [<<"in">>, <<"did:macula:charlie">>, <<"authored">>, 0.8]]),
    {ok, Rows} = resolve_link:resolve(#{subject => <<"did:macula:alice">>, direction => <<"both">>}),
    ?assertEqual(2, length(Rows)).

traversal_returns_every_hop() ->
    rows([<<"entity">>, <<"hop">>], [[<<"did:macula:bob">>, 1], [<<"did:macula:charlie">>, 2]]),
    {ok, Rows} = resolve_link:resolve(#{subject => <<"did:macula:alice">>, depth => 3}),
    ?assertEqual([1, 2], [maps:get(<<"hop">>, R) || R <- Rows]).

traversal_in_walks_edges_backwards() ->
    rows([<<"entity">>, <<"hop">>], [[<<"did:macula:zed">>, 1]]),
    {ok, [_]} = resolve_link:resolve(#{subject => <<"did:macula:alice">>, depth => 2,
                                       direction => <<"in">>}),
    [{Query, _}] = store_calls(),
    ?assertNotEqual(nomatch, binary:match(Query, <<"object: $subject">>)),
    ?assertEqual(nomatch, binary:match(Query, <<"subject: $subject">>)).

an_unknown_direction_is_refused() ->
    ?assertEqual({error, invalid_direction},
                 resolve_link:resolve(#{subject => <<"a">>, direction => <<"sideways">>})),
    ?assertEqual({error, invalid_direction},
                 resolve_link:resolve(#{subject => <<"a">>, depth => 2, direction => <<"sideways">>})).

a_depth_below_one_is_refused() ->
    ?assertEqual({error, invalid_depth}, resolve_link:resolve(#{subject => <<"a">>, depth => 0})).

%% One call with depth 10^9 on a cyclic graph would hold the store's NIF for as
%% long as cozo takes, with nothing able to interrupt it.
a_depth_above_the_cap_is_refused() ->
    ?assertEqual({error, invalid_depth}, resolve_link:resolve(#{subject => <<"a">>, depth => 9})),
    ?assertEqual({error, invalid_depth},
                 resolve_link:resolve(#{subject => <<"a">>, depth => 1000000000})).

both_directions_with_a_predicate() ->
    rows([<<"direction">>, <<"entity">>, <<"confidence">>], [[<<"out">>, <<"b">>, 1.0]]),
    {ok, [_]} = resolve_link:resolve(#{subject => <<"a">>, predicate => <<"knows">>,
                                       direction => <<"both">>}),
    [{Query, Params}] = store_calls(),
    ?assertEqual(<<"knows">>, maps:get(<<"predicate">>, Params)),
    ?assertEqual(2, length(binary:matches(Query, <<"predicate: $predicate">>))).

%% A caller gets a reason it can act on, not CozoDB's colour-coded text.
a_store_failure_reaches_the_caller_as_store_error() ->
    meck:expect(mcl_graph_store, run, fun(_Q, _P) -> {error, {cozo, <<"boom">>}} end),
    ?assertEqual({error, store_error, undefined},
                 resolve_link:handle_request(#{subject => <<"a">>}, undefined)).

a_missing_subject_is_refused() ->
    ?assertEqual({error, missing_subject}, resolve_link:resolve(#{direction => <<"out">>})).

%% `direction' arrives as {text, <<"in">>} off the wire, not as a binary.
a_real_wire_call_resolves() ->
    rows([<<"subject">>, <<"predicate">>, <<"confidence">>, <<"source">>, <<"learned_at">>],
         [[<<"did:macula:charlie">>, <<"authored">>, 0.8, <<"mcl-graph">>, 1]]),
    Payload = delivered_call:delivered(#{subject => <<"did:macula:alice">>, direction => <<"in">>},
                                       delivered_call:node_key()),
    {reply, #{rows := [_]}, _} = resolve_link:handle_request(Payload, undefined).

the_reply_is_text_not_bytes() ->
    rows([<<"entity">>, <<"hop">>], [[<<"did:macula:bob">>, 1]]),
    {reply, Reply, _} = resolve_link:handle_request(#{subject => <<"a">>, depth => 2}, undefined),
    ?assertEqual(#{rows => [#{<<"entity">> => {text, <<"did:macula:bob">>}, <<"hop">> => 1}]}, Reply).

rows(Headers, Rows) ->
    meck:expect(mcl_graph_store, run,
                fun(_Q, _P) -> {ok, #{<<"headers">> => Headers, <<"rows">> => Rows}} end).

store_calls() ->
    [{Q, P} || {_, {mcl_graph_store, run, [Q, P]}, _} <- meck:history(mcl_graph_store)].
