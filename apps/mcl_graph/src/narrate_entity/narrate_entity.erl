%%% @doc narrate_entity: an entity described in a sentence.
%%%
%%% Resolves the entity with resolve_entity as a plain function call, no mesh
%%% round trip, and renders it with narrate_template. Its own capability,
%%% `mcl-graph/narrate_entity', rather than a format flag on resolve_entity: a
%%% caller that wants rows and one that wants prose ask different questions.
-module(narrate_entity).

-behaviour(macula_response).

-export([init/1, handle_request/2]).
-export([narrate/1]).

init(_Args) -> {ok, undefined}.

handle_request(Payload, State) ->
    replied(narrate(Payload), State).

replied({ok, Result}, State)    -> {reply, mcl_graph_wire:to_wire(Result), State};
replied({error, Reason}, State) -> {error, mcl_graph_wire:reason(Reason), State}.

-spec narrate(map()) -> {ok, map()} | {error, term()}.
narrate(Params) when is_map(Params) ->
    narrated(mcl_om_wire:field(entity_id, Params));
narrate(_Params) ->
    {error, missing_entity_id}.

narrated(undefined) ->
    {error, missing_entity_id};
narrated(EntityId) ->
    resolved(resolve_entity:resolve(#{entity_id => EntityId}), EntityId).

resolved({ok, Entity}, EntityId) ->
    Prose = narrate_template:narrate(#{type => entity, entity_id => EntityId, entity => Entity}),
    {ok, #{entity_id => EntityId, prose => Prose}};
resolved({error, _} = Error, _EntityId) ->
    Error.
