%%% @doc resolve_link: the links of an entity.
%%%
%%%   depth 1   direct links: `out' (subject -> object, the default), `in'
%%%             (what links to it) or `both', optionally one predicate
%%%   depth > 1 the entities reachable in up to `depth' hops, each at the
%%%             fewest hops that reach it, walking the same directions
%%%
%%% Callers reach it as `mcl-graph/resolve_link'. Rows come back as maps named
%%% by CozoDB's column headers, text as text, at most ?MAX_ROWS of them.
%%%
%%% `depth' is capped at ?MAX_DEPTH. A lookup by subject is a key-prefix scan;
%%% one by object (`in', `both') scans the links, which is why both the depth
%%% and the rows are bounded and every query carries CozoDB's timeout
%%% (mcl_graph_store:run/2).
-module(resolve_link).

-behaviour(macula_response).

-export([init/1, handle_request/2]).
-export([resolve/1]).

-define(MAX_DEPTH, 8).
-define(MAX_ROWS, 1000).

%%====================================================================
%% macula_response
%%====================================================================

init(_Args) -> {ok, undefined}.

handle_request(Payload, State) ->
    replied(resolve(Payload), State).

replied({ok, Rows}, State)      -> {reply, #{rows => mcl_graph_wire:to_wire(Rows)}, State};
replied({error, Reason}, State) -> {error, mcl_graph_wire:reason(Reason), State}.

%%====================================================================
%% API
%%====================================================================

%% Fields are read through mcl_om_wire:field/2,3, never a hard #{key := V}
%% match: a payload off the wire is `{text, _}'-keyed.
-spec resolve(map()) -> {ok, [map()]} | {error, term()}.
resolve(Params) when is_map(Params) ->
    subject(mcl_om_wire:field(subject, Params), Params);
resolve(_Params) ->
    {error, missing_subject}.

subject(undefined, _Params) ->
    {error, missing_subject};
subject(Subject, Params) ->
    dispatch(Subject, mcl_om_wire:field(predicate, Params),
             mcl_om_wire:field(depth, Params, 1),
             mcl_om_wire:field(direction, Params, <<"out">>)).

dispatch(_Subject, _Predicate, _Depth, Direction)
  when Direction =/= <<"out">>, Direction =/= <<"in">>, Direction =/= <<"both">> ->
    {error, invalid_direction};
dispatch(Subject, Predicate, 1, Direction) ->
    run(direct(Direction, Predicate), params(Subject, Predicate));
dispatch(Subject, Predicate, Depth, Direction)
  when is_integer(Depth), Depth > 1, Depth =< ?MAX_DEPTH ->
    run(traversal(Direction, filter(Predicate), Depth), params(Subject, Predicate));
dispatch(_Subject, _Predicate, _Depth, _Direction) ->
    {error, invalid_depth}.

params(Subject, undefined) -> #{<<"subject">> => Subject};
params(Subject, Predicate) -> #{<<"subject">> => Subject, <<"predicate">> => Predicate}.

filter(undefined) -> <<>>;
filter(_)         -> <<", predicate: $predicate">>.

%%====================================================================
%% Direct links
%%====================================================================

direct(<<"out">>, undefined) ->
    <<"?[predicate, object, confidence, source, learned_at] := "
      "*links{subject: $subject, predicate, object, confidence, source, learned_at}">>;
direct(<<"out">>, _Predicate) ->
    <<"?[object, confidence, source, learned_at] := "
      "*links{subject: $subject, predicate: $predicate, object, confidence, source, learned_at}">>;
direct(<<"in">>, undefined) ->
    <<"?[subject, predicate, confidence, source, learned_at] := "
      "*links{object: $subject, subject, predicate, confidence, source, learned_at}">>;
direct(<<"in">>, _Predicate) ->
    <<"?[subject, confidence, source, learned_at] := "
      "*links{object: $subject, predicate: $predicate, subject, confidence, source, learned_at}">>;
direct(<<"both">>, undefined) ->
    <<"?[direction, entity, predicate, confidence] := "
      "*links{subject: $subject, predicate, object: entity, confidence}, direction = 'out'\n"
      "?[direction, entity, predicate, confidence] := "
      "*links{object: $subject, predicate, subject: entity, confidence}, direction = 'in'">>;
direct(<<"both">>, _Predicate) ->
    <<"?[direction, entity, confidence] := "
      "*links{subject: $subject, predicate: $predicate, object: entity, confidence}, direction = 'out'\n"
      "?[direction, entity, confidence] := "
      "*links{object: $subject, predicate: $predicate, subject: entity, confidence}, direction = 'in'">>.

%%====================================================================
%% Traversal
%%====================================================================

%% `out' walks subject -> object, `in' walks object -> subject (what reaches
%% the subject), `both' starts either way and continues either way. `min(hop)'
%% keeps one row per entity, so a cycle costs a row per entity rather than one
%% per hop count.
traversal(<<"out">>, Filter, Depth) ->
    rules([{<<"subject">>, <<"object">>}], Filter, Depth);
traversal(<<"in">>, Filter, Depth) ->
    rules([{<<"object">>, <<"subject">>}], Filter, Depth);
traversal(<<"both">>, Filter, Depth) ->
    rules([{<<"subject">>, <<"object">>}, {<<"object">>, <<"subject">>}], Filter, Depth).

rules(Walks, Filter, Depth) ->
    iolist_to_binary(
      [[seed(From, To, Filter) || {From, To} <- Walks],
       [step(From, To, Filter, Depth) || {From, To} <- Walks],
       <<"?[entity, hop] := reachable[entity, hop], entity != $subject\n"
         ":order hop, entity">>]).

seed(From, To, Filter) ->
    [<<"reachable[entity, min(hop)] := *links{">>, From, <<": $subject, ">>, To,
     <<": entity">>, Filter, <<"}, hop = 1\n">>].

step(From, To, Filter, Depth) ->
    [<<"reachable[entity, min(hop)] := reachable[prev, prev_hop], *links{">>, From,
     <<": prev, ">>, To, <<": entity">>, Filter, <<"}, hop = prev_hop + 1, hop <= ">>,
     integer_to_binary(Depth), <<"\n">>].

%%====================================================================
%% Running
%%====================================================================

run(Query, Params) ->
    rows(mcl_graph_store:run(<<Query/binary, "\n:limit ", (integer_to_binary(?MAX_ROWS))/binary>>,
                             Params)).

%% CozoDB answers each row as a list in column order, the names in `headers'.
rows({ok, #{<<"headers">> := Headers, <<"rows">> := Rows}}) ->
    {ok, [maps:from_list(lists:zip(Headers, Row)) || Row <- Rows]};
rows({error, _} = Error) ->
    Error.
