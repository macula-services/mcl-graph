%%% @doc resolve_entity: an entity's attributes and a summary of its links.
%%%
%%% Returns the stored attributes plus out-degree, in-degree and the distinct
%%% predicates it uses. For the links themselves, use resolve_link. Callers
%%% reach it as `mcl-graph/resolve_entity'.
-module(resolve_entity).

-behaviour(macula_response).

-export([init/1, handle_request/2]).
-export([resolve/1]).

%%====================================================================
%% macula_response
%%====================================================================

init(_Args) -> {ok, undefined}.

handle_request(Payload, State) ->
    replied(resolve(Payload), State).

replied({ok, Result}, State)    -> {reply, mcl_graph_wire:to_wire(Result), State};
replied({error, Reason}, State) -> {error, mcl_graph_wire:reason(Reason), State}.

%%====================================================================
%% API
%%====================================================================

-spec resolve(map()) -> {ok, map()} | {error, term()}.
resolve(Params) when is_map(Params) ->
    found(mcl_om_wire:field(entity_id, Params));
resolve(_Params) ->
    {error, missing_entity_id}.

found(undefined) -> {error, missing_entity_id};
found(EntityId)  -> summarised(entity(EntityId), EntityId).

%% Each step's failure is the caller's error. A summary left out would read as
%% "no links" to a caller who cannot tell it from "the count failed".
summarised({ok, Entity}, EntityId) ->
    counted(scalar(out_degree(), EntityId), [out_degree], Entity, EntityId);
summarised({error, _} = Error, _EntityId) ->
    Error.

counted({ok, OutDegree}, [out_degree], Entity, EntityId) ->
    counted(scalar(in_degree(), EntityId), [in_degree], Entity#{out_degree => OutDegree}, EntityId);
counted({ok, InDegree}, [in_degree], Entity, EntityId) ->
    counted(scalar(predicates(), EntityId), [predicates], Entity#{in_degree => InDegree}, EntityId);
counted({ok, Predicates}, [predicates], Entity, _EntityId) ->
    {ok, Entity#{predicates => Predicates}};
counted({error, _} = Error, _Step, _Entity, _EntityId) ->
    Error.

%%====================================================================
%% Queries
%%====================================================================

entity(EntityId) ->
    Query = <<"?[attributes, first_seen, source] := "
              "*entities{id: $entity_id, attributes, first_seen, source}">>,
    row(mcl_graph_store:run(Query, #{<<"entity_id">> => EntityId}), EntityId).

row({ok, #{<<"rows">> := [[Attributes, FirstSeen, Source] | _]}}, EntityId) ->
    {ok, #{id => EntityId, attributes => Attributes, first_seen => FirstSeen, source => Source}};
row({ok, #{<<"rows">> := []}}, _EntityId) ->
    {error, entity_not_found};
row({error, _} = Error, _EntityId) ->
    Error.

%% An aggregate in the head over no matches still answers one row (0, or an
%% empty list), so an entity with no links counts as 0 rather than failing.
out_degree() -> <<"?[count(l)] := *links{subject: $entity_id, link_id: l}">>.
in_degree()  -> <<"?[count(l)] := *links{object: $entity_id, link_id: l}">>.
predicates() -> <<"?[unique(p)] := *links{subject: $entity_id, predicate: p}">>.

scalar(Query, EntityId) ->
    value(mcl_graph_store:run(Query, #{<<"entity_id">> => EntityId})).

value({ok, #{<<"rows">> := [[Value] | _]}}) -> {ok, Value};
value({ok, Unexpected})                     -> {error, {unexpected_rows, Unexpected}};
value({error, _} = Error)                   -> Error.
