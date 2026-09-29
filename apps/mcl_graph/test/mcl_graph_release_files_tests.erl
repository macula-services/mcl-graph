%% @doc The release files, asserted against each other.
%%
%% The image, the compose example and the templated configs describe one
%% running node, and nothing in the build reads them together. A `${VAR}' the
%% image does not set and compose does not require renders as a malformed term
%% and the node refuses to boot; a graph on no volume is forgotten on the first
%% recreate; a port the registry gives someone else is taken silently under host
%% networking.
-module(mcl_graph_release_files_tests).

-include_lib("eunit/include/eunit.hrl").

%% Every variable relx substitutes at boot is supplied: by the image with a
%% default, or by compose, which refuses to start without it.
every_templated_variable_is_supplied_test() ->
    Templated = lists:usort(vars_in("config/sys.config.src") ++ vars_in("config/vm.args.src")),
    Supplied = lists:usort(image_env() ++ compose_env()),
    ?assertEqual([], Templated -- Supplied).

%% The example runs an image by DIGEST, the shape macula-fleet deploys: the
%% repository fixed here, the digest from MCL_GRAPH_IMAGE_DIGEST, no tag to
%% drift and no watchtower.
the_example_runs_an_image_by_digest_test() ->
    Text = read("deploy/docker-compose.yml"),
    ?assertMatch({match, _},
                 re:run(Text, <<"^\\s+image: ghcr\\.io/macula-services/mcl-graph@\\$\\{MCL_GRAPH_IMAGE_DIGEST:\\?[^}]+\\}$">>,
                        [multiline])),
    ?assertEqual(nomatch, re:run(Text, <<":latest">>)),
    ?assertEqual(nomatch, re:run(Text, <<"watchtower">>)).

%% The graph lives at the data dir the image names, and compose mounts it there.
the_graph_is_on_the_mounted_data_dir_test() ->
    ?assertEqual({ok, [<<"/data">>]}, image_value(<<"MCL_DATA_DIR">>)),
    ?assertMatch({match, _}, re:run(read("Containerfile"), <<"VOLUME \\[\"/etc/mcl/secrets\", \"/data\"\\]">>)),
    ?assertMatch({match, _}, re:run(read("deploy/docker-compose.yml"), <<"^\\s+- \\$\\{MCL_GRAPH_DATA:-/bulk0/mcl-graph\\}:/data$">>,
                                    [multiline])).

%% Host networking makes every port fleet-wide, so the registry (macula-fleet
%% PORTS.md: mcl-graph health 8482) is the authority, and the image and compose
%% say the same.
the_health_port_is_the_registered_one_test() ->
    ?assertEqual({ok, [<<"8482">>]}, image_value(<<"MCL_HEALTH_PORT">>)),
    ?assertMatch({match, _}, re:run(read("deploy/docker-compose.yml"), <<"- MCL_HEALTH_PORT=8482\\n">>)),
    ?assertMatch({match, _}, re:run(read("Containerfile"), <<"EXPOSE 8482\\n">>)).

%% The boot claim shows its service and box on the realm's Providers desk:
%% mcl_om reads MCL_SERVICE_NAME and MCL_BOX, and the realm admits no claim that
%% does not show both. The service name is ours; the box is the deploying
%% host's to say, so compose refuses to start without it.
the_claim_carries_its_labels_test() ->
    Compose = read("deploy/docker-compose.yml"),
    ?assertMatch({match, _}, re:run(Compose, <<"- MCL_SERVICE_NAME=mcl-graph\\n">>)),
    ?assertMatch({match, _}, re:run(Compose, <<"- MCL_BOX=\\$\\{MCL_BOX:\\?">>)).

%% The version the service reports (mcl-graph/info, the boot claim) is the
%% app's and the release's.
the_versions_agree_test() ->
    #{version := Reported} = mcl_graph_service:info(),
    _ = application:load(mcl_graph),
    {ok, App} = application:get_key(mcl_graph, vsn),
    {match, [Release]} = re:run(read("rebar.config"), <<"\\{release, \\{mcl_graph, \"([^\"]+)\"\\}">>,
                                [{capture, all_but_first, binary}]),
    ?assertEqual({Reported, Reported}, {list_to_binary(App), Release}).

%%==============================================================================

%% Comment lines are skipped: they name `${VAR}' in prose, not in config.
vars_in(File) ->
    Config = re:replace(read(File), <<"(?m)^\\s*(%|#).*$">>, <<>>, [global, {return, binary}]),
    case re:run(Config, <<"\\$\\{([A-Z0-9_]+)\\}">>, [global, {capture, all_but_first, binary}]) of
        {match, Ms} -> [V || [V] <- Ms];
        nomatch -> []
    end.

image_env() ->
    {match, Ms} = re:run(read("Containerfile"), <<"(?m)^ENV ([A-Z0-9_]+)=">>,
                         [global, {capture, all_but_first, binary}]),
    [V || [V] <- Ms].

image_value(Name) ->
    case re:run(read("Containerfile"), <<"(?m)^ENV ", Name/binary, "=(\\S+)">>,
                [{capture, all_but_first, binary}]) of
        {match, V} -> {ok, V};
        nomatch -> {error, {not_in_image, Name}}
    end.

compose_env() ->
    {match, Ms} = re:run(read("deploy/docker-compose.yml"), <<"(?m)^\\s+- ([A-Z0-9_]+)=">>,
                         [global, {capture, all_but_first, binary}]),
    [V || [V] <- Ms].

read(Name) ->
    {ok, Text} = file:read_file(alongside(Name)),
    Text.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).
