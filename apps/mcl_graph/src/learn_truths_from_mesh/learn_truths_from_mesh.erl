%%% @doc Hears `truth_asserted' facts and learns them.
%%%
%%% Passive ingestion, beside learn_link's RPC path: each fact's {subject,
%%% predicate, object} goes through the SAME learn_link:learn/2, with the
%%% verified publisher as its provenance, so both paths share one write path and
%%% one provenance model (publisher --asserted--> subject and object).
%%%
%%% One shared, opt-in contract, not a translator for other services' own
%%% events: a producer that wants to feed the graph publishes truth_asserted
%%% itself (mcl_graph_facts has the topic).
%%%
%%% CONFIDENCE IS SET BY PROVENANCE, not by the fact's own `confidence' field:
%%% a publication macula verified is recorded at 0.7. In macula 12 every
%%% publication is signed, and a strict node (the default) drops one that does
%%% not verify before it is delivered; a node running lenient delivers it with
%%% `publisher_verified => false', and it is refused here. An actively invalid
%%% signature is a stronger negative signal than none.
%%%
%%% Re-subscribes when the subscription goes away, or when the pool it lives on
%%% dies without saying so; waits while the mesh is dark.
%%% A fact that is not a map is refused: any realm member may publish any
%%% admissible term, and one that crashed this process could stop the node.
-module(learn_truths_from_mesh).
-behaviour(gen_server).

-export([start_link/0, subscribed/0, on_fact/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(RESUBSCRIBE_MS, 5_000).
%% Whether the subscription is held, where /health can read it without waiting
%% on a subscriber busy learning a burst of facts.
-define(HELD, {?MODULE, held}).
-define(VERIFIED_CONFIDENCE, 0.7).

-record(st, {sub :: reference() | undefined,
             %% The pool the subscription lives on, watched: a pool that is
             %% killed sends no macula_event_gone (macula#26).
             pool_mon :: reference() | undefined}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Whether the truth_asserted subscription is held.
-spec subscribed() -> boolean().
subscribed() ->
    persistent_term:get(?HELD, false).

%% @doc Learn one heard fact. Exported for tests.
-spec on_fact(binary(), term(), map()) -> ok.
on_fact(Topic, Payload, Meta) ->
    learn(verified(Meta), Payload, Topic).

init([]) ->
    process_flag(trap_exit, true),
    held(false),
    self() ! subscribe,
    {ok, #st{}}.

handle_call(_Req, _From, St) ->
    {reply, {error, unknown_call}, St}.

handle_cast(_Msg, St) -> {noreply, St}.

handle_info(subscribe, St) ->
    {noreply, subscribe(mcl_om:mesh_handles(), St)};
handle_info({macula_event, _Ref, Topic, Payload, Meta}, St) ->
    ok = on_fact(Topic, Payload, Meta),
    {noreply, St};
handle_info({macula_event_gone, Ref, _Reason}, #st{sub = Ref} = St) ->
    {noreply, lost(St)};
handle_info({'DOWN', Mon, process, _Pool, Reason}, #st{pool_mon = Mon} = St) ->
    logger:warning("learn_truths_from_mesh: the pool went down (~p); resubscribing", [Reason]),
    {noreply, lost(St)};
handle_info(_Info, St) ->
    {noreply, St}.

terminate(_Reason, _St) ->
    held(false).

held(Held) ->
    persistent_term:put(?HELD, Held),
    ok.

%%====================================================================
%% Subscribing
%%====================================================================

%% The pool can die between being found and being used; that is the mesh's
%% weather, not a fault here, so it is retried rather than spent on restarts.
subscribe({ok, Pool, Realm}, St) ->
    Topic = mcl_graph_facts:topic(mcl_graph_facts:realm_name(), truth_asserted),
    subscribed(pool_call(fun() -> macula:subscribe(Pool, Realm, Topic, self()) end), Topic,
               St#st{pool_mon = erlang:monitor(process, Pool)});
subscribe({error, mesh_unavailable}, St) ->
    retry(St).

subscribed({ok, Ref}, _Topic, St) ->
    held(true),
    St#st{sub = Ref};
subscribed(Error, Topic, St) ->
    logger:warning("learn_truths_from_mesh: subscribing to ~ts failed, retrying: ~p", [Topic, Error]),
    retry(unwatched(St)).

%% The subscription is gone: stop watching its pool and subscribe again, now.
lost(St) ->
    held(false),
    self() ! subscribe,
    unwatched(St#st{sub = undefined}).

unwatched(#st{pool_mon = undefined} = St) -> St;
unwatched(#st{pool_mon = Mon} = St) ->
    erlang:demonitor(Mon, [flush]),
    St#st{pool_mon = undefined}.

pool_call(Call) ->
    try Call() catch exit:Reason -> {error, {pool_gone, Reason}} end.

retry(St) ->
    erlang:send_after(?RESUBSCRIBE_MS, self(), subscribe),
    St.

%%====================================================================
%% Learning
%%====================================================================

verified(#{publisher_verified := true, publisher := Publisher}) -> {ok, Publisher};
verified(_Unverified)                                          -> refused.

learn({ok, Publisher}, Payload, _Topic) when is_map(Payload) ->
    learned(learn_link:learn(Payload#{confidence => ?VERIFIED_CONFIDENCE}, Publisher));
learn({ok, _Publisher}, _NotAMap, Topic) ->
    logger:warning("learn_truths_from_mesh: refused a ~ts fact that is not a map", [Topic]);
learn(refused, _Payload, Topic) ->
    logger:warning("learn_truths_from_mesh: refused a ~ts fact whose publisher did not verify",
                   [Topic]).

learned({ok, _Result}) ->
    ok;
learned({error, Reason}) ->
    logger:warning("learn_truths_from_mesh: fact not learned: ~p", [Reason]).
