%% @doc The release config, asserted in a way relx does not: relx copies
%% config/sys.config.src unvalidated and substitutes every ${VAR} at boot, so a
%% broken or missing line shows up only on the fleet. This fills every
%% placeholder with a dummy, parses the result and checks what must be there.
-module(mcl_graph_sys_config_tests).

-include_lib("eunit/include/eunit.hrl").

sys_config_template_parses_after_substitution_test() ->
    _ = parsed_sys_config().

%% mcl-graph names its KEM key (macula-fleet#7): callers seal to it, and a clear
%% caller is still answered (its capabilities are `preferred', the default). A
%% release that dropped the line would answer every call in the clear and look
%% healthy, so the baked config is asserted, not assumed.
kem_advertise_enabled_test() ->
    Macula = proplists:get_value(macula, parsed_sys_config()),
    ?assertEqual(enabled, proplists:get_value(kem_advertise, Macula)).

parsed_sys_config() ->
    {ok, Bin} = file:read_file("config/sys.config.src"),
    Substituted = re:replace(Bin, <<"\\$\\{[A-Z_]+\\}">>, <<"0">>, [global, {return, list}]),
    {ok, Tokens, _} = erl_scan:string(Substituted),
    case erl_parse:parse_term(Tokens) of
        {ok, Config} ->
            Config;
        {error, {Line, Mod, Msg}} ->
            erlang:error({sys_config_parse_failed, Line, Mod, lists:flatten(Msg)})
    end.
