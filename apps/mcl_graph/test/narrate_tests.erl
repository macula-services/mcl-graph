%% @doc narrate_entity and narrate_link: the graph described in sentences.
%%
%% The prose comes from narrate_template, sentence per triple: no model, no
%% network, cannot fail. The link cases feed it the rows resolve_link REALLY
%% returns (binary-keyed, one shape per direction and for traversal); its
%% predecessor matched atom keys and crashed on every real row.
-module(narrate_tests).

-include_lib("eunit/include/eunit.hrl").

narrate_test_() ->
    {foreach,
     fun() -> meck:new(mcl_graph_store, [non_strict]) end,
     fun(_) -> meck:unload(mcl_graph_store) end,
     [fun an_entity_is_described/0,
      fun an_entity_needs_an_id/0,
      fun an_unknown_entity_is_not_described/0,
      fun outgoing_links_are_described/0,
      fun incoming_links_are_described/0,
      fun links_both_ways_are_described/0,
      fun a_traversal_is_described/0,
      fun no_links_is_said_plainly/0,
      fun links_need_a_subject/0,
      fun the_reply_is_text_not_bytes/0]}.

an_entity_is_described() ->
    known_entity(),
    {ok, #{entity_id := <<"did:macula:alice">>, prose := Prose}} =
        narrate_entity:narrate(#{entity_id => <<"did:macula:alice">>}),
    ?assertEqual(<<"did:macula:alice has 3 outgoing and 2 incoming link(s), via: knows, authored.">>,
                 Prose).

an_entity_needs_an_id() ->
    ?assertEqual({error, missing_entity_id}, narrate_entity:narrate(#{})).

an_unknown_entity_is_not_described() ->
    meck:expect(mcl_graph_store, run, fun(_Q, _P) -> {ok, #{<<"rows">> => []}} end),
    ?assertEqual({error, entity_not_found},
                 narrate_entity:narrate(#{entity_id => <<"did:macula:nobody">>})).

outgoing_links_are_described() ->
    rows([<<"predicate">>, <<"object">>, <<"confidence">>, <<"source">>, <<"learned_at">>],
         [[<<"knows">>, <<"did:macula:bob">>, 1.0, <<"mcl-graph">>, 1],
          [<<"authored">>, <<"doc:1">>, 1.0, <<"mcl-graph">>, 1]]),
    ?assertEqual(<<"did:macula:alice knows did:macula:bob. did:macula:alice authored doc:1.">>,
                 prose(#{subject => <<"did:macula:alice">>})).

incoming_links_are_described() ->
    rows([<<"subject">>, <<"predicate">>, <<"confidence">>, <<"source">>, <<"learned_at">>],
         [[<<"did:macula:charlie">>, <<"knows">>, 1.0, <<"mcl-graph">>, 1]]),
    ?assertEqual(<<"did:macula:charlie knows did:macula:alice.">>,
                 prose(#{subject => <<"did:macula:alice">>, direction => <<"in">>})).

links_both_ways_are_described() ->
    rows([<<"direction">>, <<"entity">>, <<"predicate">>, <<"confidence">>],
         [[<<"out">>, <<"did:macula:bob">>, <<"knows">>, 1.0],
          [<<"in">>, <<"did:macula:charlie">>, <<"authored">>, 0.8]]),
    ?assertEqual(<<"did:macula:alice knows did:macula:bob. did:macula:charlie authored did:macula:alice.">>,
                 prose(#{subject => <<"did:macula:alice">>, direction => <<"both">>})).

a_traversal_is_described() ->
    rows([<<"entity">>, <<"hop">>], [[<<"did:macula:bob">>, 1], [<<"did:macula:dave">>, 2]]),
    ?assertEqual(<<"did:macula:alice reaches did:macula:bob in 1 hop. "
                   "did:macula:alice reaches did:macula:dave in 2 hops.">>,
                 prose(#{subject => <<"did:macula:alice">>, depth => 2})).

no_links_is_said_plainly() ->
    rows([<<"predicate">>, <<"object">>, <<"confidence">>, <<"source">>, <<"learned_at">>], []),
    ?assertEqual(<<"No links found.">>, prose(#{subject => <<"did:macula:alice">>})).

links_need_a_subject() ->
    ?assertEqual({error, missing_subject}, narrate_link:narrate(#{})).

the_reply_is_text_not_bytes() ->
    rows([<<"predicate">>, <<"object">>, <<"confidence">>, <<"source">>, <<"learned_at">>],
         [[<<"knows">>, <<"did:macula:bob">>, 1.0, <<"mcl-graph">>, 1]]),
    {reply, Reply, _} = narrate_link:handle_request(#{subject => <<"did:macula:alice">>}, undefined),
    ?assertEqual(#{subject => {text, <<"did:macula:alice">>},
                   prose => {text, <<"did:macula:alice knows did:macula:bob.">>}}, Reply).

prose(Params) ->
    {ok, #{prose := Prose}} = narrate_link:narrate(Params),
    Prose.

rows(Headers, Rows) ->
    meck:expect(mcl_graph_store, run,
                fun(_Q, _P) -> {ok, #{<<"headers">> => Headers, <<"rows">> => Rows}} end).

known_entity() ->
    meck:expect(mcl_graph_store, run, fun(Query, _P) -> answer(Query) end).

answer(Query) ->
    answer(binary:match(Query, <<"unique(p)">>),
           binary:match(Query, <<"subject: $entity_id, link_id">>),
           binary:match(Query, <<"object: $entity_id, link_id">>)).

answer({_, _}, nomatch, nomatch) -> {ok, #{<<"rows">> => [[[<<"knows">>, <<"authored">>]]]}};
answer(nomatch, {_, _}, nomatch) -> {ok, #{<<"rows">> => [[3]]}};
answer(nomatch, nomatch, {_, _}) -> {ok, #{<<"rows">> => [[2]]}};
answer(nomatch, nomatch, nomatch) ->
    {ok, #{<<"rows">> => [[#{}, 1788244318000, <<"mcl-graph">>]]}}.
