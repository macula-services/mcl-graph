%% @doc learn_link: the write path, its facts, and its provenance.
%%
%% mcl_graph_store is mocked, so these run without the NIF (mcl_graph_store_tests
%% covers the real CozoDB). Params reaching the store stay binary-keyed: they are
%% Datalog variable bindings, not RPC fields.
-module(learn_link_tests).

-include_lib("eunit/include/eunit.hrl").

-define(PROC, <<"mcl-graph/learn_link">>).

learn_link_test_() ->
    {foreach,
     fun() ->
             meck:new(mcl_graph_store, [non_strict]),
             meck:new(mcl_graph_facts, [passthrough]),
             ok
     end,
     fun(_) -> meck:unload(mcl_graph_facts), meck:unload(mcl_graph_store) end,
     [fun creates_both_entities/0,
      fun reuses_an_existing_entity/0,
      fun a_missing_subject_is_refused/0,
      fun a_missing_predicate_is_refused/0,
      fun a_missing_object_is_refused/0,
      fun publishes_link_learned/0,
      fun publishes_entity_learned_only_for_new_entities/0,
      fun stores_metadata_as_the_entity_attributes/0,
      fun carries_the_caller_s_confidence/0,
      fun a_store_failure_is_the_caller_s_error/0,
      fun records_the_caller_as_provenance/0,
      fun records_no_provenance_without_a_caller/0,
      fun a_valid_asserted_by_is_used_when_there_is_no_wire_caller/0,
      fun a_valid_asserted_by_wins_over_the_wire_caller/0,
      fun an_invalid_asserted_by_with_no_wire_caller_records_nothing/0,
      fun an_invalid_asserted_by_falls_back_to_the_wire_caller/0,
      fun an_asserted_by_bound_to_another_procedure_is_refused/0,
      fun the_reply_is_text_not_bytes/0,
      fun a_real_wire_call_is_learned_with_its_caller/0,
      fun a_real_wire_asserted_by_is_verified/0]}.

%%------------------------------------------------------------------------------
%% The write path
%%------------------------------------------------------------------------------

creates_both_entities() ->
    every_entity_is_new(),
    {ok, Result} = learn_link:learn(triple()),
    ?assertEqual(2, maps:get(entities_new, Result)),
    ?assert(is_binary(maps:get(link_id, Result))),
    ?assert(entity_inserted(<<"did:macula:alice">>)),
    ?assert(entity_inserted(<<"did:macula:bob">>)).

reuses_an_existing_entity() ->
    entity_already_known(<<"did:macula:alice">>),
    {ok, Result} = learn_link:learn(triple()),
    ?assertEqual(1, maps:get(entities_new, Result)).

a_missing_subject_is_refused() ->
    ?assertEqual({error, missing_required_fields},
                 learn_link:learn(maps:remove(subject, triple()))).

a_missing_predicate_is_refused() ->
    ?assertEqual({error, missing_required_fields},
                 learn_link:learn(maps:remove(predicate, triple()))).

a_missing_object_is_refused() ->
    ?assertEqual({error, missing_required_fields},
                 learn_link:learn(maps:remove(object, triple()))).

publishes_link_learned() ->
    every_entity_is_new(),
    {ok, _} = learn_link:learn((triple())#{predicate => <<"authored">>}),
    [Fact] = facts(link_learned),
    ?assertMatch(#{subject := <<"did:macula:alice">>, predicate := <<"authored">>,
                   object := <<"did:macula:bob">>}, Fact).

publishes_entity_learned_only_for_new_entities() ->
    entity_already_known(<<"did:macula:alice">>),
    {ok, _} = learn_link:learn(triple()),
    ?assertMatch([#{entity_id := <<"did:macula:bob">>}], facts(entity_learned)).

stores_metadata_as_the_entity_attributes() ->
    every_entity_is_new(),
    Metadata = #{<<"context">> => <<"introduction">>},
    {ok, _} = learn_link:learn((triple())#{metadata => Metadata}),
    Attrs = [maps:get(<<"attrs">>, P) || {Q, P} <- store_calls(),
                                         binary:match(Q, <<":insert entities">>) =/= nomatch],
    ?assertEqual([Metadata, Metadata], Attrs).

carries_the_caller_s_confidence() ->
    every_entity_is_new(),
    {ok, _} = learn_link:learn((triple())#{confidence => 0.85}),
    [Fact] = facts(link_learned),
    ?assertEqual(0.85, maps:get(confidence, Fact)).

%% Nothing durably recorded is not a success.
a_store_failure_is_the_caller_s_error() ->
    meck:expect(mcl_graph_store, run, fun(_Q, _P) -> {error, database_closed} end),
    ?assertEqual({error, database_closed}, learn_link:learn(triple())).

%%------------------------------------------------------------------------------
%% Provenance: the caller becomes part of the graph
%%------------------------------------------------------------------------------

records_the_caller_as_provenance() ->
    every_entity_is_new(),
    Caller = <<1:256>>,
    {ok, _} = learn_link:learn(triple(), Caller),
    CallerHex = binary:encode_hex(Caller, lowercase),
    ?assert(entity_inserted(CallerHex)),
    Asserted = asserted_links(),
    ?assertEqual([{CallerHex, <<"did:macula:alice">>}, {CallerHex, <<"did:macula:bob">>}],
                 lists:sort([{S, O} || #{<<"subject">> := S, <<"object">> := O} <- Asserted])),
    ?assert(lists:all(fun(#{<<"confidence">> := C}) -> C =:= 1.0 end, Asserted)),
    ?assertEqual(2, length([F || #{predicate := <<"asserted">>} = F <- facts(link_learned)])).

records_no_provenance_without_a_caller() ->
    every_entity_is_new(),
    {ok, #{entities_new := 2}} = learn_link:learn(triple()),
    ?assertEqual([], asserted_links()).

a_valid_asserted_by_is_used_when_there_is_no_wire_caller() ->
    every_entity_is_new(),
    Key = delivered_call:node_key(),
    Identity = delivered_call:node_id(Key),
    {reply, _, _} = learn_link:handle_request(
                      (triple())#{asserted_by => asserted_by(Key, Identity, ?PROC)}, undefined),
    ?assertEqual([hex(Identity)], asserters()).

%% The wire caller of a relayed call is the relay; a valid claim names the one
%% it relays for.
a_valid_asserted_by_wins_over_the_wire_caller() ->
    every_entity_is_new(),
    Key = delivered_call:node_key(),
    Identity = delivered_call:node_id(Key),
    {reply, _, _} = learn_link:handle_request(
                      (triple())#{caller => <<2:256>>,
                                  asserted_by => asserted_by(Key, Identity, ?PROC)}, undefined),
    ?assertEqual([hex(Identity)], asserters()).

an_invalid_asserted_by_with_no_wire_caller_records_nothing() ->
    every_entity_is_new(),
    Owner = delivered_call:node_key(),
    Impostor = delivered_call:node_key(),
    {reply, _, _} = learn_link:handle_request(
                      (triple())#{asserted_by => asserted_by(Impostor, delivered_call:node_id(Owner), ?PROC)},
                      undefined),
    ?assertEqual([], asserted_links()).

%% A forged claim can neither borrow an identity nor cost the relay the
%% provenance its own connection earned.
an_invalid_asserted_by_falls_back_to_the_wire_caller() ->
    every_entity_is_new(),
    Owner = delivered_call:node_key(),
    Impostor = delivered_call:node_key(),
    {reply, _, _} = learn_link:handle_request(
                      (triple())#{caller => <<3:256>>,
                                  asserted_by => asserted_by(Impostor, delivered_call:node_id(Owner), ?PROC)},
                      undefined),
    ?assertEqual([hex(<<3:256>>)], asserters()).

an_asserted_by_bound_to_another_procedure_is_refused() ->
    every_entity_is_new(),
    Key = delivered_call:node_key(),
    Identity = delivered_call:node_id(Key),
    {reply, _, _} = learn_link:handle_request(
                      (triple())#{asserted_by => asserted_by(Key, Identity, <<"mcl-graph/other">>)},
                      undefined),
    ?assertEqual([], asserted_links()).

the_reply_is_text_not_bytes() ->
    every_entity_is_new(),
    {reply, Reply, _} = learn_link:handle_request(triple(), undefined),
    ?assertMatch(#{link_id := {text, _}, entities_new := 2}, Reply).

%%------------------------------------------------------------------------------
%% Through macula's own codec: what a desk really receives
%%------------------------------------------------------------------------------

a_real_wire_call_is_learned_with_its_caller() ->
    every_entity_is_new(),
    Caller = delivered_call:node_key(),
    Payload = delivered_call:delivered(triple(), Caller),
    {reply, #{entities_new := 2}, _} = learn_link:handle_request(Payload, undefined),
    ?assert(entity_inserted(<<"did:macula:alice">>)),
    ?assertEqual([hex(delivered_call:node_id(Caller))], asserters()).

a_real_wire_asserted_by_is_verified() ->
    every_entity_is_new(),
    Relay = delivered_call:node_key(),
    Key = delivered_call:node_key(),
    Identity = delivered_call:node_id(Key),
    Payload = delivered_call:delivered(
                (triple())#{asserted_by => asserted_by(Key, Identity, ?PROC)}, Relay),
    {reply, _, _} = learn_link:handle_request(Payload, undefined),
    ?assertEqual([hex(Identity)], asserters()).

%%------------------------------------------------------------------------------
%% Helpers
%%------------------------------------------------------------------------------

triple() ->
    #{subject => <<"did:macula:alice">>, predicate => <<"knows">>, object => <<"did:macula:bob">>}.

asserted_by(Key, Identity, Procedure) ->
    Ts = erlang:system_time(millisecond),
    Sig = macula_node_keys:sign(mcl_om_ownership_proof:message(Identity, Ts, Procedure), Key),
    #{identity => hex(Identity),
      proof => #{timestamp => Ts,
                 signature => hex(Sig),
                 public => hex(macula_node_keys:public_key(Key))}}.

hex(Bin) -> binary:encode_hex(Bin, lowercase).

%% Every `:insert' succeeds: every entity is new.
every_entity_is_new() ->
    meck:expect(mcl_graph_store, run, fun(_Q, _P) -> {ok, #{<<"rows">> => [[]]}} end),
    quiet_facts().

%% `Known''s `:insert' fails with CozoDB's own wording for a key collision.
entity_already_known(Known) ->
    meck:expect(mcl_graph_store, run,
                fun(_Q, #{<<"entity_id">> := Id}) when Id =:= Known ->
                        {error, {cozo, <<"transact::assertion_failure\n  x when executing against relation 'entities'\n"
                                         "  Assertion failure for [\"x\"] of entities: key exists in database">>}};
                   (_Q, _P) ->
                        {ok, #{<<"rows">> => [[]]}}
                end),
    quiet_facts().

quiet_facts() ->
    meck:expect(mcl_graph_facts, publish_entity_learned, fun(_) -> ok end),
    meck:expect(mcl_graph_facts, publish_link_learned, fun(_) -> ok end).

facts(entity_learned) ->
    [F || {_, {mcl_graph_facts, publish_entity_learned, [F]}, _} <- meck:history(mcl_graph_facts)];
facts(link_learned) ->
    [F || {_, {mcl_graph_facts, publish_link_learned, [F]}, _} <- meck:history(mcl_graph_facts)].

store_calls() ->
    [{Q, P} || {_, {mcl_graph_store, run, [Q, P]}, _} <- meck:history(mcl_graph_store)].

entity_inserted(Id) ->
    lists:any(fun({Q, P}) ->
                      binary:match(Q, <<":insert entities">>) =/= nomatch
                          andalso maps:get(<<"entity_id">>, P, undefined) =:= Id
              end, store_calls()).

asserted_links() ->
    [P || {_Q, P} <- store_calls(), maps:get(<<"predicate">>, P, undefined) =:= <<"asserted">>].

asserters() ->
    lists:usort([S || #{<<"subject">> := S} <- asserted_links()]).
