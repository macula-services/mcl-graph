%%% @doc The CozoDB NIF (native/mcl_graph_nif), loaded from this app's priv/.
%%%
%%% Stateless: the database handle it returns lives in mcl_graph_store's state.
%%% There is no pure-Erlang fallback for a graph database, so a NIF that did not
%%% load is loud: on_load fails, the module does not load, and the first call
%%% raises `undef'. is_loaded/0 says which of the two it is.
-module(mcl_graph_nif).

-export([open/1, run_query/3, run_script/2, close/1, is_loaded/0]).

-on_load(on_load/0).

on_load() ->
    erlang:load_nif(filename:join(code:priv_dir(mcl_graph), "mcl_graph_nif"), 0).

-spec is_loaded() -> boolean().
is_loaded() ->
    erlang:module_loaded(?MODULE).

-spec open(binary()) -> {ok, reference()} | {error, term()}.
open(_Path) -> erlang:nif_error(nif_not_loaded).

-spec run_query(reference(), binary(), map()) -> {ok, map()} | {error, term()}.
run_query(_Resource, _Query, _Params) -> erlang:nif_error(nif_not_loaded).

-spec run_script(reference(), binary()) -> {ok, map()} | {error, term()}.
run_script(_Resource, _Script) -> erlang:nif_error(nif_not_loaded).

-spec close(reference()) -> ok | {error, term()}.
close(_Resource) -> erlang:nif_error(nif_not_loaded).
