%% @doc Top supervisor.
%%
%% Two children: mcl_graph_store, which opens CozoDB, holds the NIF resource and
%% owns the schema, and learn_truths_from_mesh, which hears `truth_asserted'
%% facts and learns them. The store starts first: the subscriber writes into it.
-module(mcl_graph_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 30},
    {ok, {SupFlags, [worker(mcl_graph_store), worker(learn_truths_from_mesh)]}}.

worker(Module) ->
    #{id => Module,
      start => {Module, start_link, []},
      restart => permanent,
      shutdown => 5000,
      type => worker,
      modules => [Module]}.
