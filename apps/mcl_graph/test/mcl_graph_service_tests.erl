%% @doc The service contract, asserted locally.
%%
%% mcl_om resolves the six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% `-behaviour(mcl_om_service)' attribute turns that into a compile error; this
%% suite asserts what the compiler cannot see: the shapes inside the callbacks,
%% the names the mesh reaches this service by, and the pinned runtime.
-module(mcl_graph_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_graph).
-define(SERVICE, mcl_graph_service).

exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    ?assertEqual([], [F || {N, A} = F <- Required,
                           not erlang:function_exported(?SERVICE, N, A)]).

declares_the_behaviour_test() ->
    Attrs = ?SERVICE:module_info(attributes),
    ?assert(lists:member(mcl_om_service, proplists:get_value(behaviour, Attrs, []))).

%% The OTP application is snake_case, the repo, image and mesh name kebab-case.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    ?assertEqual(<<"mcl-graph">>, Wire),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

%% The names a caller reaches this service by, as `mcl-graph/<name>'. Growing
%% or renaming this list changes the public surface, so it is spelled out.
capabilities_are_the_five_desks_test() ->
    Caps = ?SERVICE:capabilities(),
    ?assertEqual([<<"learn_link">>, <<"narrate_entity">>, <<"narrate_link">>,
                  <<"resolve_entity">>, <<"resolve_link">>],
                 lists:sort([N || #{name := N} <- Caps])).

every_capability_is_served_by_its_desk_test() ->
    [?assertEqual({binary_to_atom(N), []}, H) || #{name := N, handler := H} <- ?SERVICE:capabilities()],
    [?assertEqual(1, V) || #{version := V} <- ?SERVICE:capabilities()],
    [?assertEqual(open, A) || #{auth := A} <- ?SERVICE:capabilities()].

every_handler_is_a_macula_response_test() ->
    [begin
         {module, M} = code:ensure_loaded(M),
         ?assert(erlang:function_exported(M, init, 1)),
         ?assert(erlang:function_exported(M, handle_request, 2))
     end || #{handler := {M, _}} <- ?SERVICE:capabilities()].

identity_spec_names_the_scope_test() ->
    #{scope := Scope, actions := Actions, resources := Resources, ttl_days := Ttl} =
        ?SERVICE:identity_spec(),
    ?assertEqual(<<"mcl-graph">>, Scope),
    ?assert(lists:all(fun is_binary/1, Actions ++ Resources)),
    ?assert(is_integer(Ttl) andalso Ttl > 0).

%%==============================================================================
%% Health: a store that is not open is down; a deaf subscriber is degraded
%%==============================================================================

health_test_() ->
    {foreach,
     fun() ->
             meck:new(mcl_graph_store, [non_strict]),
             meck:new(learn_truths_from_mesh, [non_strict])
     end,
     fun(_) -> meck:unload(learn_truths_from_mesh), meck:unload(mcl_graph_store) end,
     [fun() ->
              meck:expect(mcl_graph_store, is_open, fun() -> true end),
              meck:expect(learn_truths_from_mesh, subscribed, fun() -> true end),
              ?assertEqual(ok, ?SERVICE:health())
      end,
      fun() ->
              meck:expect(mcl_graph_store, is_open, fun() -> false end),
              meck:expect(learn_truths_from_mesh, subscribed, fun() -> true end),
              ?assertEqual({down, store_not_open}, ?SERVICE:health())
      end,
      fun() ->
              meck:expect(mcl_graph_store, is_open, fun() -> true end),
              meck:expect(learn_truths_from_mesh, subscribed, fun() -> false end),
              ?assertEqual({degraded, not_hearing_truths}, ?SERVICE:health())
      end]}.

%%==============================================================================
%% The runtime is pinned in four places and they must agree
%%==============================================================================

%% The builder stage and lint each ASSERT an OTP release in a check step, because
%% a dated image tag names a date, not a release. Those, .tool-versions and the VM
%% running this test must agree to the patch: a floating `erlang:28' once shipped
%% OTP 28.5 to the fleet while every check stayed green.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    Check = "\\{<<\"([0-9]+\\.[0-9]+\\.[0-9]+)\">>, true\\} -> halt\\(0\\);",
    Image = pinned("Containerfile", Check),
    Ci = pinned(".github/workflows/lint-and-test.yml", Check),
    Tools = pinned(".tool-versions", "^erlang ([0-9]+\\.[0-9]+\\.[0-9]+)$"),
    ?assertEqual([Image], lists:usort([Image, Ci, Tools, running_otp()])).

%% THE FLEET'S ROCKSDB IMAGE PAIR, by one dated tag and digest: the builder
%% carries OTP 28.4.3 with ML-DSA, rebar3, Rust, cmake and a C++ toolchain for
%% the CozoDB NIF; the runtime is the same Debian with what the release loads.
%% CI builds in exactly the builder, so a green lint is about what ships.
images_are_the_dated_and_digest_pinned_rocksdb_pair_test() ->
    Pin = ":([0-9]{8}-[0-9]{4}@sha256:[0-9a-f]{64})",
    Builder = pinned("Containerfile", "^FROM ghcr\\.io/macula-io/macula-ci-otp-rocksdb" ++ Pin ++ " AS builder$"),
    Runtime = pinned("Containerfile", "^FROM ghcr\\.io/macula-io/macula-pq-runtime-rocksdb" ++ Pin ++ "$"),
    Ci = pinned(".github/workflows/lint-and-test.yml",
                "^\\s+image: ghcr\\.io/macula-io/macula-ci-otp-rocksdb" ++ Pin ++ "$"),
    ?assertEqual(Builder, Ci),
    ?assertEqual(tag(Builder), tag(Runtime)).

tag(Pin) -> hd(binary:split(Pin, <<"@">>)).

%% THE NIF IS BUILT FOR THE BASELINE x86-64, on purpose. cozorocks compiles
%% RocksDB with -mavx2 and friends whenever Rust's target features include them,
%% and the beam boxes are Celeron J4105s without AVX2: an image built for the
%% build machine's CPU dies there with SIGILL. build-nif.sh pins the target CPU
%% instead of inheriting whatever RUSTFLAGS the image or a shell carries.
the_nif_is_built_for_the_baseline_cpu_test() ->
    ?assertEqual(<<"x86-64">>,
                 pinned("native/build-nif.sh", "^\\s+export RUSTFLAGS=\"-C target-cpu=(x86-64)\"$")),
    Native = [F || F <- ["Containerfile", ".github/workflows/lint-and-test.yml", "native/build-nif.sh"],
                   match =:= re:run(read(F), <<"target-cpu=native|-march=native">>, [{capture, none}])],
    ?assertEqual([], Native).

%% The service is nothing without the mesh: mcl_om's {mesh, required} stops a
%% boot missing MCL_REALM, MCL_REALM_KEY or the pinned stations and names each
%% one. It must sit in the mcl_om block, the one mcl_om reads.
the_service_requires_the_mesh_test() ->
    ?assertEqual(<<"required">>,
                 pinned("config/sys.config.src",
                        "(?s)^\\s+\\{mcl_om, \\[(?:(?!^\\s+\\]\\},?$).)*?^\\s+\\{mesh,\\s+(required)\\},?$")).

%% SIGNED BY DIGEST: build-push hands the pushed digest to macula-ci-images'
%% attest-image.yml, pinned by full commit (the signing identity), so a box can
%% refuse any mcl-graph digest this repository's CI did not build.
the_image_is_signed_by_the_pinned_attest_workflow_test() ->
    W = ".github/workflows/build-push.yml",
    ?assertMatch(<<_/binary>>,
                 pinned(W, "^\\s+uses: macula-io/macula-ci-images/\\.github/workflows/attest-image\\.yml@([0-9a-f]{40})$")),
    ?assertEqual(<<"ghcr.io/macula-services/mcl-graph">>,
                 pinned(W, "^\\s+image: (ghcr\\.io/macula-services/mcl-graph)$")),
    ?assertEqual(<<"needs.build-and-push.outputs.digest">>,
                 pinned(W, "^\\s+digest: \\$\\{\\{ (needs\\.build-and-push\\.outputs\\.digest) \\}\\}$")),
    %% The chain that carries the digest to the attest job. Without either link
    %% the digest is empty, the attest job is skipped, and the run is green with
    %% an unsigned image.
    ?assertEqual(<<"steps.push.outputs.digest">>,
                 pinned(W, "^\\s+digest: \\$\\{\\{ (steps\\.push\\.outputs\\.digest) \\}\\}$")),
    ?assertEqual(<<"push">>,
                 pinned(W, "^\\s+id: (push)\\n\\s+uses: docker/build-push-action@")).

%% Every action a workflow runs is pinned by full commit: a tag moves.
every_action_is_pinned_by_commit_test() ->
    Unpinned = [{W, U} || W <- [".github/workflows/build-push.yml", ".github/workflows/lint-and-test.yml"],
                          U <- uses(W), nomatch =:= re:run(U, <<"@[0-9a-f]{40}$">>)],
    ?assertEqual([], Unpinned).

uses(Workflow) ->
    case re:run(read(Workflow), <<"^\\s+(?:-\\s+)?uses:\\s+(\\S+)">>,
                [multiline, global, {capture, all_but_first, binary}]) of
        {match, Found} -> [U || [U] <- Found];
        nomatch -> []
    end.

%% No box follows a tag (macula-fleet#14, #15): the build publishes a v* tag's version only,
%% and main :main and :<sha>; any other ref ends in exit 1. macula-fleet pins a release by
%% digest once attest has signed it, so nothing here moves :latest.
nothing_moves_latest_test() ->
    {ok, Body} = file:read_file(alongside(".github/workflows/build-push.yml")),
    Has = fun(Bin) -> ?assertNotEqual(nomatch, binary:match(Body, Bin)) end,
    Has(<<"refs/tags/v*)    echo \"tags=$img:${GITHUB_REF#refs/tags/v}\" >> \"$GITHUB_OUTPUT\" ;;">>),
    Has(<<"refs/heads/main) echo \"tags=$img:main,$img:${GITHUB_SHA}\" >> \"$GITHUB_OUTPUT\" ;;">>),
    Has(<<"exit 1 ;;">>),
    ?assertEqual(nomatch, binary:match(Body, <<"promote-latest">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"imagetools create">>)),
    ?assertEqual(nomatch, binary:match(Body, <<",$img:latest">>)).

%% The image says which commit IT was built from, not its base image's.
the_image_carries_its_revision_test() ->
    ?assertEqual(<<"REVISION">>, pinned("Containerfile", "^ARG (REVISION)=unknown$")),
    ?assertEqual(<<"${REVISION}">>,
                 pinned("Containerfile", "^LABEL org\\.opencontainers\\.image\\.revision=\"([^\"]+)\"$")),
    ?assertEqual(<<"${{ github.sha }}">>,
                 pinned(".github/workflows/build-push.yml", "^\\s+REVISION=(.+)$")).

read(Relative) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    Text.

running_otp() ->
    {ok, Version} = file:read_file(filename:join([code:root_dir(), "releases",
                                                  erlang:system_info(otp_release),
                                                  "OTP_VERSION"])),
    string:trim(Version).

pinned(Relative, Pattern) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    {match, [Version]} = re:run(Text, Pattern, [multiline, {capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) -> climb(filename:dirname(Dir), Name, Left - 1).
