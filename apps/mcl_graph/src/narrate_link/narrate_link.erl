%%% @doc narrate_link: an entity's links described, one sentence per link.
%%%
%%% Takes the same parameters as resolve_link (subject, predicate, direction,
%%% depth), resolves them with resolve_link as a plain function call and renders
%%% the rows with narrate_template. Callers reach it as `mcl-graph/narrate_link'.
-module(narrate_link).

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
    narrated(mcl_om_wire:field(subject, Params), Params);
narrate(_Params) ->
    {error, missing_subject}.

narrated(undefined, _Params) ->
    {error, missing_subject};
narrated(Subject, Params) ->
    resolved(resolve_link:resolve(Params), Subject).

resolved({ok, Links}, Subject) ->
    Prose = narrate_template:narrate(#{type => links, subject => Subject, links => Links}),
    {ok, #{subject => Subject, prose => Prose}};
resolved({error, _} = Error, _Subject) ->
    Error.
