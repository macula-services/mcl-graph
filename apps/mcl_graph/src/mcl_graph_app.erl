%% @doc OTP application entry.
%%
%% mcl_om:boot/1 wires the mesh, the realm identity, the capabilities and
%% health, then starts this service. mcl_om owns no store for it: the graph
%% lives in CozoDB, which mcl_graph_store opens through this repo's own NIF.
-module(mcl_graph_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> mcl_om:boot(mcl_graph_service).

stop(_State) -> ok.
