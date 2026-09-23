%% @doc The shape this service's replies and facts leave in.
%%
%% Every string it sends is human-readable, so every binary leaves as
%% `{text, Bin}' (CBOR text) rather than as a bare binary (CBOR bytes), which
%% every non-BEAM consumer renders as hex. JSON booleans out of CozoDB leave as
%% 1/0, because there are no booleans on the wire, and JSON null leaves as null.
-module(mcl_graph_wire).

-export([to_wire/1, reason/1]).

-spec to_wire(term()) -> term().
to_wire(B) when is_binary(B) -> {text, B};
to_wire({text, B}) when is_binary(B) -> {text, B};
to_wire(true) -> 1;
to_wire(false) -> 0;
to_wire(nil) -> undefined;
to_wire(L) when is_list(L) -> [to_wire(E) || E <- L];
to_wire(M) when is_map(M) -> maps:map(fun(_K, V) -> to_wire(V) end, M);
to_wire(Other) -> Other.

%% @doc The error a caller receives. A CozoDB failure is logged in full and
%% reaches the caller as `store_error': its text names this service's internals
%% and arrives at a remote caller as a name only anyway.
-spec reason(term()) -> term().
reason({cozo, Text}) ->
    logger:warning("mcl-graph: store refused a query: ~ts", [Text]),
    store_error;
reason(Reason) ->
    Reason.
