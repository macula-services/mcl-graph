%%% @doc The graph described in sentences: one per triple, deterministic.
%%%
%%% No model and no network, so it cannot fail and costs nothing. It reads the
%%% rows resolve_link really returns, which are named by CozoDB's column headers
%%% and differ by query: outgoing links name `object', incoming ones `subject',
%%% both-ways rows carry `direction' and `entity', and a traversal gives
%%% `entity' and `hop'.
-module(narrate_template).

-export([narrate/1]).

-spec narrate(map()) -> binary().
narrate(#{type := entity, entity_id := EntityId, entity := Entity}) ->
    entity_sentence(EntityId, Entity);
narrate(#{type := links, subject := Subject, links := Links}) ->
    links_sentence(Subject, Links).

entity_sentence(EntityId, Entity) ->
    iolist_to_binary([EntityId, <<" has ">>, integer_to_binary(maps:get(out_degree, Entity, 0)),
                      <<" outgoing and ">>, integer_to_binary(maps:get(in_degree, Entity, 0)),
                      <<" incoming link(s)">>, predicates(maps:get(predicates, Entity, [])),
                      <<".">>]).

predicates([])         -> <<>>;
predicates(Predicates) -> [<<", via: ">>, lists:join(<<", ">>, Predicates)].

links_sentence(_Subject, []) ->
    <<"No links found.">>;
links_sentence(Subject, Links) ->
    iolist_to_binary(lists:join(<<" ">>, [sentence(Subject, L) || L <- Links])).

sentence(Subject, #{<<"direction">> := <<"out">>, <<"entity">> := E, <<"predicate">> := P}) ->
    triple(Subject, P, E);
sentence(Subject, #{<<"direction">> := <<"in">>, <<"entity">> := E, <<"predicate">> := P}) ->
    triple(E, P, Subject);
sentence(Subject, #{<<"entity">> := E, <<"hop">> := Hop}) ->
    [Subject, <<" reaches ">>, E, <<" in ">>, integer_to_binary(Hop), hops(Hop), <<".">>];
sentence(Subject, #{<<"predicate">> := P, <<"object">> := O}) ->
    triple(Subject, P, O);
sentence(Subject, #{<<"subject">> := S, <<"predicate">> := P}) ->
    triple(S, P, Subject);
sentence(Subject, #{<<"object">> := O}) ->
    triple(Subject, <<"links to">>, O);
sentence(Subject, #{<<"subject">> := S}) ->
    triple(S, <<"links to">>, Subject).

triple(S, P, O) -> [S, <<" ">>, P, <<" ">>, O, <<".">>].

hops(1) -> <<" hop">>;
hops(_) -> <<" hops">>.
