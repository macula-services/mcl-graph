%% @doc Registering this service's procedures does not wait for the network.
%%
%% mcl_om:boot/1 registers the capabilities from the service's start/2 with a
%% gen_server call of the default 5 s patience. mcl_om up to 0.33.2 advertised
%% every procedure over the network INSIDE that call, so enough procedures or a
%% slow station failed the boot on the timeout: mcl-rag's eighteen did on msi00,
%% 2026-09-29, crash-looping every boot. 0.33.3 replies at once and advertises
%% right after. This holds that behaviour for mcl-graph whatever mcl_om it
%% resolves, because the floor alone only states a number.
-module(mcl_graph_register_tests).

-include_lib("eunit/include/eunit.hrl").

%% Advertising starts by asking mcl_om_identity for the pool; here that takes
%% 3 s. Inside the call, register would take at least that long.
register_replies_before_advertising_test_() ->
    {timeout, 30,
     {setup, fun start/0, fun stop/1,
      fun(_) ->
          [{timeout, 20, fun() ->
              Caps = mcl_om_info:with_info(mcl_graph_service:capabilities()),
              {Us, Result} = timer:tc(fun() -> mcl_om_capabilities:register(Caps) end),
              ?assertEqual(ok, Result),
              ?assert(Us < 1_000_000, {register_took_us, Us})
          end}]
      end}}.

start() ->
    ok = meck:new(mcl_om_identity, [passthrough]),
    ok = meck:expect(mcl_om_identity, macula_client, fun() -> timer:sleep(3_000), {error, no_pool} end),
    ok = meck:expect(mcl_om_identity, identity_key, fun() -> {error, no_identity_key} end),
    ok = meck:expect(mcl_om_identity, realm, fun() -> {error, no_realm} end),
    ok = meck:expect(mcl_om_identity, org, fun() -> <<"mcl-graph">> end),
    {ok, Pid} = mcl_om_capabilities:start_link(),
    unlink(Pid),
    Pid.

stop(Pid) ->
    Ref = monitor(process, Pid),
    exit(Pid, kill),
    receive {'DOWN', Ref, process, Pid, _} -> ok after 5_000 -> ok end,
    meck:unload(mcl_om_identity).
