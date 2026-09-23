%% @doc The store against the real CozoDB NIF, on a real RocksDB directory.
%%
%% Everything else mocks mcl_graph_store. This is the one place the NIF, the
%% schema and the Datalog the desks send meet an actual database, including the
%% restart that has to find the schema already there.
-module(mcl_graph_store_tests).

-include_lib("eunit/include/eunit.hrl").

store_test_() ->
    {foreach,
     fun() ->
             Dir = filename:join(["/tmp", "mcl_graph_store_tests",
                                  integer_to_list(erlang:unique_integer([positive]))]),
             ok = application:set_env(mcl_graph, data_dir, Dir),
             %% The facts go nowhere: this is about the database.
             meck:new(mcl_graph_facts, [passthrough]),
             meck:expect(mcl_graph_facts, publish_entity_learned, fun(_) -> ok end),
             meck:expect(mcl_graph_facts, publish_link_learned, fun(_) -> ok end),
             {ok, Pid} = mcl_graph_store:start_link(),
             unlink(Pid),
             Dir
     end,
     fun(Dir) ->
             stop(),
             meck:unload(mcl_graph_facts),
             application:unset_env(mcl_graph, data_dir),
             file:del_dir_r(Dir)
     end,
     [fun the_nif_is_loaded/0,
      fun an_open_store_says_so/0,
      fun a_learned_link_resolves/0,
      fun an_entity_is_inserted_once/0,
      fun traversal_reaches_two_hops/0,
      fun a_restart_finds_the_schema_and_the_data/0,
      fun wire_shaped_params_are_stored_as_plain_json/0,
      fun a_bad_query_is_an_error_not_a_crash/0,
      fun a_cycle_is_walked_once_per_entity/0,
      fun a_query_carries_a_timeout/0]}.

%% `undef' from a NIF call can mean on_load failed; say which.
the_nif_is_loaded() ->
    ?assert(mcl_graph_nif:is_loaded()).

an_open_store_says_so() ->
    ?assert(mcl_graph_store:is_open()).

a_learned_link_resolves() ->
    ok = learn_link_triple(<<"alice">>, <<"knows">>, <<"bob">>),
    {ok, [Row]} = resolve_link:resolve(#{subject => <<"alice">>}),
    ?assertMatch(#{<<"predicate">> := <<"knows">>, <<"object">> := <<"bob">>,
                   <<"confidence">> := 1.0}, Row).

an_entity_is_inserted_once() ->
    ok = learn_link_triple(<<"alice">>, <<"knows">>, <<"bob">>),
    {ok, #{entities_new := New}} = learn_link:learn(#{subject => <<"alice">>, predicate => <<"likes">>,
                                                      object => <<"carol">>}),
    ?assertEqual(1, New),
    {ok, Entity} = resolve_entity:resolve(#{entity_id => <<"alice">>}),
    ?assertMatch(#{out_degree := 2, in_degree := 0}, Entity).

traversal_reaches_two_hops() ->
    ok = learn_link_triple(<<"a">>, <<"to">>, <<"b">>),
    ok = learn_link_triple(<<"b">>, <<"to">>, <<"c">>),
    {ok, Rows} = resolve_link:resolve(#{subject => <<"a">>, depth => 2}),
    ?assertEqual([{<<"b">>, 1}, {<<"c">>, 2}],
                 [{E, H} || #{<<"entity">> := E, <<"hop">> := H} <- Rows]),
    {ok, Back} = resolve_link:resolve(#{subject => <<"c">>, depth => 2, direction => <<"in">>}),
    ?assertEqual([<<"b">>, <<"a">>], [E || #{<<"entity">> := E} <- Back]).

%% The second boot meets relations and indexes the first one made.
a_restart_finds_the_schema_and_the_data() ->
    ok = learn_link_triple(<<"alice">>, <<"knows">>, <<"bob">>),
    stop(),
    {ok, Pid} = mcl_graph_store:start_link(),
    unlink(Pid),
    ?assertMatch({ok, [_]}, resolve_link:resolve(#{subject => <<"alice">>})).

%% Attributes are JSON, and JSON keys are strings: the {text, _} keys and
%% values a caller's metadata arrives with are stored as plain text.
wire_shaped_params_are_stored_as_plain_json() ->
    Metadata = #{{text, <<"context">>} => {text, <<"intro">>}, {text, <<"n">>} => 3},
    {ok, _} = learn_link:learn(#{subject => <<"alice">>, predicate => <<"knows">>,
                                 object => <<"bob">>, metadata => Metadata}),
    {ok, #{attributes := Attrs}} = resolve_entity:resolve(#{entity_id => <<"alice">>}),
    ?assertEqual(#{<<"context">> => <<"intro">>, <<"n">> => 3}, Attrs).

a_bad_query_is_an_error_not_a_crash() ->
    ?assertMatch({error, {cozo, _}}, mcl_graph_store:run(<<"?[x] := not datalog">>, #{})),
    ?assert(mcl_graph_store:is_open()).

%% a -> b -> c -> a: at the depth cap every entity appears once, at the fewest
%% hops that reach it, instead of once per hop count.
a_cycle_is_walked_once_per_entity() ->
    ok = learn_link_triple(<<"a">>, <<"to">>, <<"b">>),
    ok = learn_link_triple(<<"b">>, <<"to">>, <<"c">>),
    ok = learn_link_triple(<<"c">>, <<"to">>, <<"a">>),
    {ok, Rows} = resolve_link:resolve(#{subject => <<"a">>, depth => 8}),
    ?assertEqual([{<<"b">>, 1}, {<<"c">>, 2}],
                 [{E, H} || #{<<"entity">> := E, <<"hop">> := H} <- Rows]).

%% CozoDB's own timeout is what can stop a query inside the NIF; the store's
%% gen_server timeout cannot. Every query leaves the store with one, and the
%% writes above prove CozoDB accepts it on `:insert' and `:put' too.
a_query_carries_a_timeout() ->
    Bounded = mcl_graph_store:bounded(<<"?[x] := x = 1">>),
    ?assertMatch({match, _}, re:run(Bounded, "\\n:timeout [0-9]+$")),
    ?assertMatch({ok, #{<<"rows">> := [[1]]}}, mcl_graph_store:run(<<"?[x] := x = 1">>, #{})).

learn_link_triple(S, P, O) ->
    {ok, _} = learn_link:learn(#{subject => S, predicate => P, object => O}),
    ok.

stop() ->
    stopped(whereis(mcl_graph_store)).

stopped(undefined) -> ok;
stopped(Pid) ->
    Ref = monitor(process, Pid),
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> ok after 5000 -> error(store_did_not_stop) end.
