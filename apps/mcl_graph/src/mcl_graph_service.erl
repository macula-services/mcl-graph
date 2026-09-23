%%% @doc The mcl_om service contract: what mcl-graph is and may do.
%%%
%%% An embeddable relational-graph database backed by CozoDB (Datalog over
%%% RocksDB). Each instance keeps its own graph on local disk. Callers reach it
%%% as `mcl-graph/<name>':
%%%
%%%   resolve_link    links of an entity: direct, filtered, reverse, N-hop
%%%   resolve_entity  an entity's attributes and a summary of its links
%%%   learn_link      record a relationship; unknown entities are created
%%%   narrate_entity  an entity described in a sentence
%%%   narrate_link    an entity's links described, sentence per link
%%%
%%% It publishes entity_learned and link_learned and hears truth_asserted; see
%%% mcl_graph_facts. Consumers compose one knowledge graph from many instances
%%% by calling resolve_link on each (pull) or by subscribing to the facts
%%% (push).
-module(mcl_graph_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

info() ->
    #{name => <<"mcl-graph">>,
      version => <<"0.1.0">>,
      description => <<"Relational-graph database (CozoDB) as a mesh service">>}.

%% The realm name the topics carry must be the realm the pool is in.
start(_Opts) ->
    ok = mcl_graph_facts:check_realm_name(),
    mcl_graph_sup:start_link().

stop(_State) -> ok.

%% Down when the store is not open: every capability would fail. Degraded when
%% the truths subscriber is deaf: the graph still answers, but hears nothing.
health() ->
    health(mcl_graph_store:is_open(), learn_truths_from_mesh:subscribed()).

health(false, _Hearing) -> {down, store_not_open};
health(true, false)     -> {degraded, not_hearing_truths};
health(true, true)      -> ok.

%% Open procedures: the graph is a commons any realm member may read and add
%% to. What it learns carries the caller as provenance (learn_link).
capabilities() ->
    [capability(Desk) || Desk <- [resolve_link, resolve_entity, learn_link,
                                  narrate_entity, narrate_link]].

capability(Desk) ->
    #{name => atom_to_binary(Desk, utf8),
      version => 1,
      handler => {Desk, []},
      auth => open}.

%% THE AUTHORITY THIS SERVICE ASKS THE REALM FOR, and nothing more: its own
%% procedures and the two topics it publishes.
identity_spec() ->
    #{scope => <<"mcl-graph">>,
      actions => [<<"resolve">>, <<"learn">>, <<"narrate">>],
      resources => [<<"entity_learned">>, <<"link_learned">>],
      ttl_days => 30}.
