%%% @doc The graph's public contract on the mesh.
%%%
%%% Topics are app tier, org `mcl-graph', app `graph', domain `knowledge', for
%%% example `io.macula/mcl-graph/graph/knowledge/link_learned_v1':
%%%
%%%   entity_learned_v1  published: learn_link met an entity this instance did
%%%                      not know. entity_id, attributes, source, learned_at.
%%%   link_learned_v1    published: a relationship was recorded. subject,
%%%                      predicate, object, confidence, source, learned_at.
%%%   truth_asserted_v1  heard, never published here: the shared, opt-in
%%%                      contract any producer publishes a {subject, predicate,
%%%                      object} onto for the graph to learn. The graph owns its
%%%                      schema, so it lives under the graph's org.
%%%
%%% A consumer composing a knowledge graph from several instances subscribes to
%%% entity_learned and link_learned and upserts vertices and edges. Text leaves
%%% as text (mcl_graph_wire); times are milliseconds since the epoch.
-module(mcl_graph_facts).

-export([publish_entity_learned/1, publish_link_learned/1,
         entity_learned/1, link_learned/1,
         topic/2, realm_name/0, check_realm_name/0, check_realm_name/2,
         reporter/0]).

-define(REPORTER, <<"mcl-graph">>).
-define(VERSION, 1).

-type fact() :: entity_learned | link_learned | truth_asserted.

-export_type([fact/0]).

%%------------------------------------------------------------------------------
%% Publishing
%%------------------------------------------------------------------------------

%% @doc Publish that an entity was learned. A dark mesh drops it; a refusal is
%% logged by mcl_om.
-spec publish_entity_learned(map()) -> ok.
publish_entity_learned(Fields) ->
    publish(entity_learned, entity_learned(Fields)).

-spec publish_link_learned(map()) -> ok.
publish_link_learned(Fields) ->
    publish(link_learned, link_learned(Fields)).

publish(Fact, Payload) ->
    _ = mcl_om_pubsub:publish(topic(realm_name(), Fact), mcl_graph_wire:to_wire(Payload),
                              #{mode => async_log}),
    ok.

%%------------------------------------------------------------------------------
%% Payloads, pure
%%------------------------------------------------------------------------------

-spec entity_learned(map()) -> map().
entity_learned(Fields) ->
    stamped(maps:with([entity_id, attributes, source, learned_at], Fields)).

-spec link_learned(map()) -> map().
link_learned(Fields) ->
    stamped(maps:with([subject, predicate, object, confidence, source, learned_at], Fields)).

stamped(Fact) ->
    maps:merge(#{source => ?REPORTER, learned_at => erlang:system_time(millisecond)}, Fact).

-spec reporter() -> binary().
reporter() -> ?REPORTER.

%%------------------------------------------------------------------------------
%% Topics and the realm they carry
%%------------------------------------------------------------------------------

-spec topic(binary(), fact()) -> binary().
topic(RealmName, Fact) ->
    macula_topic:app_fact(RealmName, ?REPORTER, <<"graph">>, <<"knowledge">>,
                          atom_to_binary(Fact, utf8), ?VERSION).

%% @doc Refuse to start when the realm name the topics carry is not the realm
%% the pool is in: the graph would publish where nobody listens, and hear
%% nothing, and look exactly like a quiet graph.
-spec check_realm_name() -> ok.
check_realm_name() ->
    configured(realm_name(), mcl_om:realm()).

configured(Name, {ok, Tag}) -> check_realm_name(Name, Tag);
configured(Name, Other)     -> error({mcl_graph_realm_unset, Name, Other}).

-spec check_realm_name(binary(), binary()) -> ok.
check_realm_name(Name, Tag) ->
    matched(crypto:hash(sha256, Name) =:= Tag, Name, Tag).

matched(true, _Name, _Tag) -> ok;
matched(false, Name, Tag)  -> error({mcl_graph_realm_name_mismatch, Name, Tag}).

-spec realm_name() -> binary().
realm_name() ->
    named(application:get_env(mcl_graph, realm_name, undefined)).

named(Name) when is_list(Name), Name =/= "" -> unicode:characters_to_binary(Name);
named(Name) when is_binary(Name), Name =/= <<>> -> Name;
named(_Unset) -> error({mcl_graph_realm_name_unset, realm_name}).
