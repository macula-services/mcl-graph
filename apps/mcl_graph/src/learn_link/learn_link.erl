%%% @doc learn_link: record a relationship between two entities.
%%%
%%% The write path. It ensures the subject exists (publishing entity_learned
%%% when it did not), ensures the object exists (likewise), records the link and
%%% publishes link_learned. Entities are created implicitly.
%%%
%%% "Already known" is decided in ONE round trip by CozoDB's `:insert', which
%%% fails when the key exists (`:put' would overwrite). Two racing calls for the
%%% same new entity cannot both see it missing: exactly one insert succeeds, so
%%% exactly one entity_learned is published.
%%%
%%% PROVENANCE: the caller becomes part of the graph. The caller is the
%%% wire-authenticated node id macula merges into every CALL payload, unless the
%%% payload carries a VALID `asserted_by': an identity plus an ownership proof
%%% (mcl_om_ownership_proof) bound to this procedure. A relay calling on behalf
%%% of others over its own connection names them that way; an invalid claim
%%% falls back to the wire caller and can never borrow another identity. The
%%% caller, hex-encoded, is linked `asserted' to both endpoints at confidence
%%% 1.0, so "what has X told the graph" is an ordinary resolve_link.
-module(learn_link).

-behaviour(macula_response).

-export([init/1, handle_request/2]).
-export([learn/1, learn/2]).

%% Confidence of the caller's own provenance link: we are not uncertain that
%% the caller made the call.
-define(PROVENANCE_CONFIDENCE, 1.0).
-define(ASSERTED, <<"asserted">>).
%% The procedure an `asserted_by' proof must be bound to: this capability's
%% name as callers reach it.
-define(PROCEDURE, <<"mcl-graph/learn_link">>).

%%====================================================================
%% macula_response
%%====================================================================

init(_Args) -> {ok, undefined}.

handle_request(Payload, State) ->
    replied(learn(Payload, caller(Payload)), State).

replied({ok, Result}, State)    -> {reply, mcl_graph_wire:to_wire(Result), State};
replied({error, Reason}, State) -> {error, mcl_graph_wire:reason(Reason), State}.

caller(Payload) ->
    asserted_or_wire(mcl_om_wire:field(asserted_by, Payload), mcl_om_wire:caller(Payload)).

asserted_or_wire(AssertedBy, WireCaller) when is_map(AssertedBy) ->
    verified_or_wire(verify(AssertedBy), WireCaller);
asserted_or_wire(_Absent, WireCaller) ->
    WireCaller.

verified_or_wire({ok, Identity}, _WireCaller) -> Identity;
verified_or_wire({error, _}, WireCaller)      -> WireCaller.

verify(AssertedBy) ->
    verify_identity(mcl_om_ownership_proof:decode_identity(mcl_om_wire:field(identity, AssertedBy)),
                    mcl_om_wire:field(proof, AssertedBy, #{})).

verify_identity(undefined, _Proof) ->
    {error, invalid_identity};
verify_identity(Identity, Proof) ->
    verified(mcl_om_ownership_proof:verify(Identity, Proof, ?PROCEDURE), Identity).

verified(ok, Identity)          -> {ok, Identity};
verified({error, _} = Error, _) -> Error.

%%====================================================================
%% API
%%====================================================================

%% @equiv learn(Params, undefined)
-spec learn(map()) -> {ok, map()} | {error, term()}.
learn(Params) ->
    learn(Params, undefined).

%% @doc Learn `subject --predicate--> object' from `Params', with `Caller' (a
%% node id, or undefined) as its provenance. Fields are read through
%% mcl_om_wire, so atom, binary and `{text, _}' keys all work.
-spec learn(map(), binary() | undefined) -> {ok, map()} | {error, term()}.
learn(Params, Caller) when is_map(Params) ->
    triple(mcl_om_wire:field(subject, Params), mcl_om_wire:field(predicate, Params),
           mcl_om_wire:field(object, Params), Params, Caller);
learn(_Params, _Caller) ->
    {error, missing_required_fields}.

triple(Subject, Predicate, Object, Params, Caller)
  when is_binary(Subject), is_binary(Predicate), is_binary(Object) ->
    Link = #{subject => Subject, predicate => Predicate, object => Object,
             confidence => mcl_om_wire:field(confidence, Params, 1.0),
             metadata => mcl_om_wire:field(metadata, Params, #{}),
             source => mcl_graph_facts:reporter(),
             now => erlang:system_time(millisecond)},
    subject_known(ensure_entity(Subject, Link), Link, Caller);
triple(_Subject, _Predicate, _Object, _Params, _Caller) ->
    {error, missing_required_fields}.

%%====================================================================
%% Sequential fallible steps, one function each
%%====================================================================

subject_known({ok, SubjectNew}, #{object := Object} = Link, Caller) ->
    object_known(ensure_entity(Object, Link), SubjectNew, Link, Caller);
subject_known({error, _} = Error, _Link, _Caller) ->
    Error.

object_known({ok, ObjectNew}, SubjectNew, Link, Caller) ->
    #{subject := S, predicate := P, object := O, confidence := C, now := Now} = Link,
    LinkId = link_id(S, P, O, Now),
    linked(insert_link(LinkId, S, P, O, C, Link), LinkId, SubjectNew + ObjectNew, Link, Caller);
object_known({error, _} = Error, _SubjectNew, _Link, _Caller) ->
    Error.

linked(ok, LinkId, New, #{subject := S, predicate := P, object := O, confidence := C} = Link, Caller) ->
    publish_link(S, P, O, C, Link),
    ok = record_provenance(Caller, Link),
    {ok, #{link_id => LinkId, entities_new => New}};
linked({error, _} = Error, _LinkId, _New, _Link, _Caller) ->
    Error.

%% Best effort: the write the caller asked for has already succeeded.
record_provenance(undefined, _Link) ->
    ok;
record_provenance(Caller, #{subject := S, object := O} = Link) ->
    CallerHex = binary:encode_hex(Caller, lowercase),
    asserted(ensure_entity(CallerHex, Link#{metadata => #{}}), CallerHex, [S, O], Link).

asserted({ok, _New}, CallerHex, Targets, Link) ->
    lists:foreach(fun(Target) -> assert_link(CallerHex, Target, Link) end, Targets);
asserted({error, Reason}, CallerHex, _Targets, _Link) ->
    logger:warning("learn_link: no provenance entity for ~ts: ~p", [CallerHex, Reason]).

assert_link(Caller, Target, #{now := Now} = Link) ->
    LinkId = link_id(Caller, ?ASSERTED, Target, Now),
    assert_linked(insert_link(LinkId, Caller, ?ASSERTED, Target, ?PROVENANCE_CONFIDENCE, Link),
                  Caller, Target, Link).

assert_linked(ok, Caller, Target, Link) ->
    publish_link(Caller, ?ASSERTED, Target, ?PROVENANCE_CONFIDENCE, Link);
assert_linked({error, Reason}, Caller, Target, _Link) ->
    logger:warning("learn_link: asserted link ~ts -> ~ts failed: ~p", [Caller, Target, Reason]).

%%====================================================================
%% Store
%%====================================================================

%% Creates the entity, or reports it already known, in one `:insert'.
ensure_entity(EntityId, #{metadata := Attributes, now := Now, source := Source}) ->
    Query = <<"?[id, attributes, first_seen, source] <- [[$entity_id, $attrs, $now, $source]]\n"
              ":insert entities {id => attributes, first_seen, source}">>,
    Params = #{<<"entity_id">> => EntityId, <<"attrs">> => Attributes,
               <<"now">> => Now, <<"source">> => Source},
    inserted(mcl_graph_store:run(Query, Params), EntityId, Attributes, Now, Source).

inserted({ok, _}, EntityId, Attributes, Now, Source) ->
    mcl_graph_facts:publish_entity_learned(#{entity_id => EntityId, attributes => Attributes,
                                             source => Source, learned_at => Now}),
    {ok, 1};
inserted({error, {cozo, Text} = Reason}, _EntityId, _Attributes, _Now, _Source) ->
    already_known(binary:match(Text, <<"key exists in database">>), Reason);
inserted({error, _} = Error, _EntityId, _Attributes, _Now, _Source) ->
    Error.

%% CozoDB's `:insert' collision is an assertion failure whose message ends "key
%% exists in database" (its predecessor looked for "already exist", which it
%% never says, so every second learn of an entity failed). Anything else is a
%% real failure and must reach the caller, never pass as "it existed".
already_known(nomatch, Reason) -> {error, Reason};
already_known(_Found, _Reason) -> {ok, 0}.

insert_link(LinkId, Subject, Predicate, Object, Confidence, #{source := Source, now := Now}) ->
    Query = <<"?[link_id, subject, predicate, object, confidence, source, learned_at]\n"
              "<- [[$link_id, $subject, $predicate, $object, $confidence, $source, $now]]\n"
              ":put links {subject, link_id => predicate, object, confidence, source, learned_at}">>,
    Params = #{<<"link_id">> => LinkId, <<"subject">> => Subject, <<"predicate">> => Predicate,
               <<"object">> => Object, <<"confidence">> => Confidence,
               <<"source">> => Source, <<"now">> => Now},
    put_link(mcl_graph_store:run(Query, Params)).

put_link({ok, _}) -> ok;
put_link({error, Reason} = Error) ->
    logger:warning("learn_link: link not recorded: ~p", [Reason]),
    Error.

publish_link(Subject, Predicate, Object, Confidence, #{source := Source, now := Now}) ->
    mcl_graph_facts:publish_link_learned(#{subject => Subject, predicate => Predicate,
                                           object => Object, confidence => Confidence,
                                           source => Source, learned_at => Now}).

link_id(Subject, Predicate, Object, Now) ->
    Digest = crypto:hash(sha256, <<Subject/binary, "|", Predicate/binary, "|",
                                   Object/binary, "|", (integer_to_binary(Now))/binary>>),
    binary:part(binary:encode_hex(Digest, lowercase), 0, 16).
