%% @doc resolve_entity: an entity's attributes and a summary of its links.
-module(resolve_entity_tests).

-include_lib("eunit/include/eunit.hrl").

resolve_entity_test_() ->
    {foreach,
     fun() -> meck:new(mcl_graph_store, [non_strict]) end,
     fun(_) -> meck:unload(mcl_graph_store) end,
     [fun a_known_entity_is_summarised/0,
      fun an_unknown_entity_is_not_found/0,
      fun a_missing_id_is_refused/0,
      fun a_failed_summary_is_the_caller_s_error/0,
      fun a_failed_lookup_is_the_caller_s_error/0,
      fun the_reply_is_text_not_bytes/0]}.

a_known_entity_is_summarised() ->
    known_entity(),
    {ok, Entity} = resolve_entity:resolve(#{entity_id => <<"did:macula:alice">>}),
    ?assertEqual(<<"did:macula:alice">>, maps:get(id, Entity)),
    ?assertEqual(3, maps:get(out_degree, Entity)),
    ?assertEqual(2, maps:get(in_degree, Entity)),
    ?assertEqual([<<"knows">>, <<"authored">>], maps:get(predicates, Entity)).

an_unknown_entity_is_not_found() ->
    meck:expect(mcl_graph_store, run, fun(_Q, _P) -> {ok, #{<<"rows">> => []}} end),
    ?assertEqual({error, entity_not_found},
                 resolve_entity:resolve(#{entity_id => <<"did:macula:nobody">>})).

a_missing_id_is_refused() ->
    ?assertEqual({error, missing_entity_id}, resolve_entity:resolve(#{})).

%% Not a quietly partial entity: a caller cannot tell "no links" from "the
%% count failed" if the counts are simply left out.
a_failed_summary_is_the_caller_s_error() ->
    meck:expect(mcl_graph_store, run,
                fun(Query, P) ->
                        failed_counts(binary:match(Query, <<"count(">>), Query, P)
                end),
    ?assertEqual({error, <<"no such op">>},
                 resolve_entity:resolve(#{entity_id => <<"did:macula:alice">>})).

a_failed_lookup_is_the_caller_s_error() ->
    meck:expect(mcl_graph_store, run, fun(_Q, _P) -> {error, database_closed} end),
    ?assertEqual({error, database_closed},
                 resolve_entity:resolve(#{entity_id => <<"did:macula:alice">>})).

failed_counts(nomatch, Query, _P) -> answer(Query);
failed_counts(_Found, _Query, _P) -> {error, <<"no such op">>}.

the_reply_is_text_not_bytes() ->
    known_entity(),
    {reply, Reply, _} = resolve_entity:handle_request(#{entity_id => <<"did:macula:alice">>}, undefined),
    ?assertMatch(#{id := {text, <<"did:macula:alice">>}, source := {text, <<"mcl-graph">>},
                   predicates := [{text, <<"knows">>}, {text, <<"authored">>}],
                   attributes := #{<<"name">> := {text, <<"Alice">>}}}, Reply).

%% One answer per query shape resolve_entity issues.
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
    {ok, #{<<"rows">> => [[#{<<"name">> => <<"Alice">>}, 1788244318000, <<"mcl-graph">>]]}}.
