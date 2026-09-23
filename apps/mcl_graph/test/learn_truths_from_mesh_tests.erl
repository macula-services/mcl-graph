%% @doc learn_truths_from_mesh: `truth_asserted' facts heard and learned.
%%
%% In macula 12 every publication is signed. A subscriber sees
%% `publisher_verified => true' for one that verified, and `false' only on a
%% node running the lenient `pubsub_strict_publisher_sig => false'; the strict
%% default drops it before delivery. So there is no unsigned tier any more.
-module(learn_truths_from_mesh_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TOPIC, <<"io.macula/mcl-graph/graph/knowledge/truth_asserted_v1">>).

truths_test_() ->
    {foreach,
     fun() ->
             meck:new(learn_link, [passthrough]),
             meck:expect(learn_link, learn, fun(_P, _C) -> {ok, #{link_id => <<"x">>, entities_new => 2}} end)
     end,
     fun(_) -> meck:unload(learn_link) end,
     [fun a_verified_publisher_is_learned_at_0_7/0,
      fun the_publisher_is_the_provenance/0,
      fun the_publisher_s_own_confidence_claim_is_overridden/0,
      fun an_unverified_publication_is_refused/0,
      fun a_failed_learn_does_not_crash_the_subscriber/0,
      fun a_payload_that_is_not_a_map_is_refused/0]}.

a_verified_publisher_is_learned_at_0_7() ->
    ok = learn_truths_from_mesh:on_fact(?TOPIC, triple(), meta(<<1:256>>, true)),
    [{Params, _Caller}] = learned(),
    ?assertEqual(0.7, maps:get(confidence, Params)).

the_publisher_is_the_provenance() ->
    ok = learn_truths_from_mesh:on_fact(?TOPIC, triple(), meta(<<1:256>>, true)),
    ?assertMatch([{_, <<1:256>>}], learned()).

%% Provenance decides the confidence recorded, not the producer's claim.
the_publisher_s_own_confidence_claim_is_overridden() ->
    ok = learn_truths_from_mesh:on_fact(?TOPIC, (triple())#{confidence => 1.0}, meta(<<1:256>>, true)),
    [{Params, _}] = learned(),
    ?assertEqual(0.7, maps:get(confidence, Params)).

an_unverified_publication_is_refused() ->
    ok = learn_truths_from_mesh:on_fact(?TOPIC, triple(), meta(<<2:256>>, false)),
    ?assertEqual([], learned()).

a_failed_learn_does_not_crash_the_subscriber() ->
    meck:expect(learn_link, learn, fun(_P, _C) -> {error, missing_required_fields} end),
    ?assertEqual(ok, learn_truths_from_mesh:on_fact(?TOPIC, #{}, meta(<<3:256>>, true))).

%% Any realm member may publish any admissible term. A number here once raised
%% badmap in the subscriber, and six in 30 s stopped the node.
a_payload_that_is_not_a_map_is_refused() ->
    [?assertEqual(ok, learn_truths_from_mesh:on_fact(?TOPIC, P, meta(<<5:256>>, true)))
     || P <- [42, <<"x">>, [1, 2], 1.5]],
    ?assertEqual([], learned()).

%% A pool that dies between being found and being used exits the subscribe
%% call; the subscriber retries rather than spending its supervisor's budget.
subscriber_test_() ->
    {setup,
     fun() ->
             ok = application:set_env(mcl_graph, realm_name, "io.macula"),
             meck:new(mcl_om, [non_strict]),
             meck:new(macula, [non_strict]),
             meck:expect(mcl_om, mesh_handles, fun() -> {ok, self(), <<0:256>>} end),
             meck:expect(macula, subscribe, fun(_, _, _, _) -> exit(noproc) end),
             {ok, Pid} = learn_truths_from_mesh:start_link(),
             unlink(Pid),
             Pid
     end,
     fun(Pid) ->
             exit(Pid, shutdown),
             meck:unload(macula), meck:unload(mcl_om),
             application:unset_env(mcl_graph, realm_name)
     end,
     fun(Pid) ->
             fun() ->
                     timer:sleep(100),
                     ?assert(is_process_alive(Pid)),
                     ?assertNot(learn_truths_from_mesh:subscribed())
             end
     end}.

%% Health must not wait on a subscriber busy learning a burst of facts.
subscribed_is_read_without_the_subscriber_test() ->
    ?assertNot(learn_truths_from_mesh:subscribed()).

%% A payload off macula's codec carries {text, _} keys and values: the real
%% learn_link must still find subject, predicate and object in it. The CALL
%% codec stands in for the publication's: both carry the payload through the
%% same map encoding.
real_wire_test_() ->
    {setup,
     fun() ->
             meck:new(mcl_graph_store, [non_strict]),
             meck:new(mcl_graph_facts, [passthrough]),
             meck:expect(mcl_graph_store, run, fun(_Q, _P) -> {ok, #{<<"rows">> => [[]]}} end),
             meck:expect(mcl_graph_facts, publish_entity_learned, fun(_) -> ok end),
             meck:expect(mcl_graph_facts, publish_link_learned, fun(_) -> ok end)
     end,
     fun(_) -> meck:unload(mcl_graph_facts), meck:unload(mcl_graph_store) end,
     fun a_real_wire_fact_is_learned/0}.

a_real_wire_fact_is_learned() ->
    Wire = maps:remove(caller, delivered_call:delivered(triple(), delivered_call:node_key())),
    ok = learn_truths_from_mesh:on_fact(?TOPIC, Wire, meta(<<4:256>>, true)),
    Links = [P || {_, {mcl_graph_store, run, [Q, P]}, _} <- meck:history(mcl_graph_store),
                  binary:match(Q, <<":put links">>) =/= nomatch,
                  maps:get(<<"predicate">>, P) =:= <<"knows">>],
    ?assertMatch([#{<<"subject">> := <<"did:macula:alice">>, <<"confidence">> := 0.7}], Links).

triple() ->
    #{subject => <<"did:macula:alice">>, predicate => <<"knows">>, object => <<"did:macula:bob">>}.

meta(Publisher, Verified) ->
    #{publisher => Publisher, publisher_verified => Verified, delivered_via => direct}.

learned() ->
    [{P, C} || {_, {learn_link, learn, [P, C]}, _} <- meck:history(learn_link)].
