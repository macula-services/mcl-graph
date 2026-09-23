%%% @doc The CozoDB store: opens the database, owns the schema, runs queries.
%%%
%%% The CozoDB resource handle lives in this gen_server's state; every query
%%% goes through run/2 and the NIF. Two relations:
%%%
%%%   entities  one row per known entity, created implicitly by learn_link
%%%     id          String  key, e.g. "did:macula:abc"
%%%     attributes  Json    the metadata the learning call carried
%%%     first_seen  Int     epoch ms
%%%     source      String  which service learned it
%%%
%%%   links     one row per recorded relationship
%%%     subject     String  key, first: a lookup by subject is a prefix scan
%%%     link_id     String  key: sha256(subject|predicate|object|learned_at), 16 hex
%%%     predicate, object  String
%%%     confidence  Float   0.0 to 1.0
%%%     source      String
%%%     learned_at  Int     epoch ms
%%%
%%% NO SECONDARY INDEXES. CozoDB 0.7.6's `::index create' answers wrong: with an
%%% index on links' subject, `*links{subject: $s, ...}' returned no rows for a
%%% subject that had one, and the same query without the index found it. So the
%%% subject leads the key instead, and a lookup by object scans.
-module(mcl_graph_store).
-behaviour(gen_server).

-export([start_link/0, is_open/0, run/2, bounded/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% CozoDB's own timeout, in seconds, is what can stop a query inside the NIF:
%% the gen_server call timeout only stops the caller waiting, while the store
%% process stays inside the NIF and every later call queues behind it. So
%% CozoDB gives up first.
-define(COZO_TIMEOUT_S, 10).
-define(QUERY_TIMEOUT_MS, 30_000).

%% ONE STATEMENT PER SCRIPT. CozoDB runs only the LAST `:create' of a script
%% that holds several: `entities' and `links' together in one script created
%% `links' alone, and every learn_link then failed with relation_not_found.
%% The key columns are before `=>': without the split every column is key, and
%% `:put'-ing an existing id with new attributes inserts a second row instead.
-define(SCHEMA, [
    <<":create entities {id: String => attributes: Json default {}, "
      "first_seen: Int, source: String}">>,
    <<":create links {subject: String, link_id: String => predicate: String, "
      "object: String, confidence: Float default 1.0, source: String, learned_at: Int}">>
]).

-record(state, {resource :: reference()}).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec is_open() -> boolean().
is_open() ->
    open(whereis(?MODULE)).

open(undefined) -> false;
open(_Pid)      -> true.

%% @doc Run one Datalog query with its variable bindings, bounded by CozoDB's
%% timeout. Bindings may carry whatever a caller's payload decoded to,
%% `{text, Bin}' keys and values included; they reach CozoDB as plain JSON.
%% CozoDB's failures come back as `{cozo, Text}', its colour codes removed.
-spec run(binary(), map()) -> {ok, map()} | {error, term()}.
run(Query, Params) ->
    failed(gen_server:call(?MODULE, {run, bounded(Query), json(Params)}, ?QUERY_TIMEOUT_MS)).

failed({error, Reason}) when is_binary(Reason) -> {error, {cozo, readable(Reason)}};
failed(Result)                                 -> Result.

%% @doc `Query' with CozoDB's timeout. Exported for tests.
-spec bounded(binary()) -> binary().
bounded(Query) ->
    <<Query/binary, "\n:timeout ", (integer_to_binary(?COZO_TIMEOUT_S))/binary>>.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    DataDir = application:get_env(mcl_graph, data_dir, "/tmp/mcl_graph"),
    ok = filelib:ensure_path(DataDir),
    %% The NIF takes the path as a Rust String, which rustler accepts only
    %% from a binary; the release config gives a charlist.
    opened(mcl_graph_nif:open(unicode:characters_to_binary(DataDir)), DataDir).

opened({ok, Resource}, DataDir) ->
    schema_ready(schema(Resource, ?SCHEMA), Resource, DataDir);
opened({error, Reason}, DataDir) ->
    logger:error("mcl_graph_store: CozoDB did not open at ~ts: ~p", [DataDir, Reason]),
    {stop, {cozo_open_failed, Reason}}.

schema_ready(ok, Resource, DataDir) ->
    logger:info("mcl_graph_store: CozoDB open at ~ts", [DataDir]),
    {ok, #state{resource = Resource}};
schema_ready({error, Reason}, Resource, _DataDir) ->
    catch mcl_graph_nif:close(Resource),
    logger:error("mcl_graph_store: schema failed: ~ts", [readable(Reason)]),
    {stop, {schema_failed, readable(Reason)}}.

handle_call({run, Query, Params}, _From, #state{resource = R} = State) ->
    {reply, mcl_graph_nif:run_query(R, Query, Params), State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

terminate(_Reason, #state{resource = R}) ->
    catch mcl_graph_nif:close(R),
    ok.

%%====================================================================
%% Schema
%%====================================================================

schema(_Resource, []) ->
    ok;
schema(Resource, [Statement | Rest]) ->
    next(stepped(mcl_graph_nif:run_script(Resource, Statement)), Resource, Rest).

next(ok, Resource, Rest)  -> schema(Resource, Rest);
next(Error, _Resource, _) -> Error.

%% Every boot after the first meets the relations the first one made, which
%% CozoDB reports as "conflicts with an existing one": the expected no-op.
stepped({ok, _}) -> ok;
stepped({error, Reason}) -> existing(readable(Reason), Reason).

existing(Text, Reason) ->
    known(binary:match(Text, <<"conflicts with an existing">>), Reason).

known(nomatch, Reason) -> {error, Reason};
known(_Found, _Reason) -> ok.

%% CozoDB's messages carry ANSI colour codes: with them a substring match
%% never succeeds and a log line prints as a list of bytes.
readable(Reason) when is_binary(Reason) ->
    re:replace(Reason, <<"\e\\[[0-9;]*m">>, <<>>, [global, {return, binary}]);
readable(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).

%%====================================================================
%% Bindings as JSON
%%====================================================================

%% JSON object keys are strings, and a payload's nested maps arrive from the
%% wire with `{text, Key}' keys and `{text, Value}' values.
json({text, B}) when is_binary(B) -> B;
json(M) when is_map(M) -> maps:from_list([{json_key(K), json(V)} || {K, V} <- maps:to_list(M)]);
json(L) when is_list(L) -> [json(E) || E <- L];
json(Other) -> Other.

json_key({text, B}) when is_binary(B) -> B;
json_key(A) when is_atom(A) -> atom_to_binary(A, utf8);
json_key(K) -> K.
