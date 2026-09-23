%% @doc The graph's public contract on the mesh: its topics and fact payloads.
-module(mcl_graph_facts_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM_NAME, <<"io.macula">>).

%%------------------------------------------------------------------------------
%% Topics: app tier, org mcl-graph, app graph, domain knowledge
%%------------------------------------------------------------------------------

entity_learned_topic_test() ->
    ?assertEqual(<<"io.macula/mcl-graph/graph/knowledge/entity_learned_v1">>,
                 mcl_graph_facts:topic(?REALM_NAME, entity_learned)).

link_learned_topic_test() ->
    ?assertEqual(<<"io.macula/mcl-graph/graph/knowledge/link_learned_v1">>,
                 mcl_graph_facts:topic(?REALM_NAME, link_learned)).

%% The shared, opt-in contract producers publish onto for the graph to learn.
%% The graph owns its schema, so it lives under the graph's org.
truth_asserted_topic_test() ->
    ?assertEqual(<<"io.macula/mcl-graph/graph/knowledge/truth_asserted_v1">>,
                 mcl_graph_facts:topic(?REALM_NAME, truth_asserted)).

%%------------------------------------------------------------------------------
%% The realm name the topics carry must be the realm the pool is in
%%------------------------------------------------------------------------------

a_realm_name_matching_the_tag_is_accepted_test() ->
    ?assertEqual(ok, mcl_graph_facts:check_realm_name(?REALM_NAME,
                                                      crypto:hash(sha256, ?REALM_NAME))).

a_realm_name_not_matching_the_tag_refuses_to_start_test() ->
    ?assertError({mcl_graph_realm_name_mismatch, ?REALM_NAME, _},
                 mcl_graph_facts:check_realm_name(?REALM_NAME, <<0:256>>)).

an_unset_realm_name_refuses_to_start_test() ->
    application:unset_env(mcl_graph, realm_name),
    ?assertError({mcl_graph_realm_name_unset, realm_name}, mcl_graph_facts:realm_name()).

%%------------------------------------------------------------------------------
%% Payloads
%%------------------------------------------------------------------------------

%% The topic names the fact and its version; the payload does not repeat them.
entity_learned_carries_the_entity_test() ->
    Fact = mcl_graph_facts:entity_learned(#{entity_id => <<"did:macula:alice">>,
                                            attributes => #{}, learned_at => 7}),
    ?assertEqual(#{entity_id => <<"did:macula:alice">>, attributes => #{},
                   source => <<"mcl-graph">>, learned_at => 7}, Fact).

link_learned_carries_the_triple_test() ->
    Fact = mcl_graph_facts:link_learned(#{subject => <<"a">>, predicate => <<"knows">>,
                                          object => <<"b">>, confidence => 0.9,
                                          learned_at => 7}),
    ?assertEqual(#{subject => <<"a">>, predicate => <<"knows">>, object => <<"b">>,
                   confidence => 0.9, source => <<"mcl-graph">>, learned_at => 7}, Fact).

%% What goes on the wire is text, not bytes, on the graph's own topic.
publishing_sends_text_on_the_graph_topic_test_() ->
    {setup,
     fun() ->
             ok = application:set_env(mcl_graph, realm_name, "io.macula"),
             meck:new(mcl_om_pubsub, [non_strict]),
             meck:expect(mcl_om_pubsub, publish, fun(_T, _P, _O) -> ok end)
     end,
     fun(_) -> meck:unload(mcl_om_pubsub), application:unset_env(mcl_graph, realm_name) end,
     fun() ->
             ok = mcl_graph_facts:publish_link_learned(
                    #{subject => <<"a">>, predicate => <<"knows">>, object => <<"b">>,
                      confidence => 1.0, learned_at => 7}),
             [{_, {mcl_om_pubsub, publish, [Topic, Payload, Opts]}, ok}] =
                 meck:history(mcl_om_pubsub),
             ?assertEqual(<<"io.macula/mcl-graph/graph/knowledge/link_learned_v1">>, Topic),
             ?assertEqual({text, <<"knows">>}, maps:get(predicate, Payload)),
             ?assertEqual(#{mode => async_log}, Opts)
     end}.
