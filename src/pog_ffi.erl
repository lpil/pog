-module(pog_ffi).

-export([query/4, query_extended/2, start/1, coerce/1, null/0, checkout/1]).

-include_lib("pog/include/pog_Config.hrl").
-include_lib("pg_types/include/pg_types.hrl").

null() ->
    null.

coerce(Value) ->
    Value.

%% Use correct defaults for SSL connections when SSL is enabled.
%% Peers have to be verified & cacerts are fetched directly from the system.
%%
%% `server_name_indication` should be set to the value of the Host, because the
%% connection to Postgres uses a TCP connection that get upgraded to TLS, and
%% the TLS socket is sent as is, meaning the Hostname is lost when ssl module
%% get the socket. server_name_indication overrides that behaviour and send
%% the correct Hostname to the ssl module.
%% `customize_hostname_check` should be set to with the verify hostname match
%% with HTTPS, because otherwise wildcards certificaties (i.e. *.example.com)
%% will not be handled correctly.
default_ssl_options(Host, Ssl) ->
  case Ssl of
    ssl_disabled -> {false, []};
    ssl_unverified -> {true, [{verify, verify_none}]};
    ssl_verified -> {true, [
      {verify, verify_peer},
      {cacerts, public_key:cacerts_get()},
      {server_name_indication, binary_to_list(Host)},
      {customize_hostname_check, [
        {match_fun, public_key:pkix_verify_hostname_match_fun(https)}
      ]}
    ]}
  end.

start(Config) ->
    % Unfortunately this has to be supplied via global mutable state currently.
    application:set_env(pg_types, timestamp_config, integer_system_time_microseconds),
    #config{
        pool_name = PoolName,
        host = Host,
        port = Port,
        database = Database,
        user = User,
        password = Password,
        ssl = Ssl,
        connection_parameters = ConnectionParameters,
        pool_size = PoolSize,
        queue_target = QueueTarget,
        queue_interval = QueueInterval,
        idle_interval = IdleInterval,
        trace = Trace,
        ip_version = IpVersion,
        rows_as_map = RowsAsMap
    } = Config,
    {SslActivated, SslOptions} = default_ssl_options(Host, Ssl),
    Options1 = #{
        host => Host,
        port => Port,
        database => Database,
        user => User,
        ssl => SslActivated,
        ssl_options => SslOptions,
        connection_parameters => ConnectionParameters,
        pool_size => PoolSize,
        queue_target => QueueTarget,
        queue_interval => QueueInterval,
        idle_interval => IdleInterval,
        trace => Trace,
        decode_opts => [{return_rows_as_maps, RowsAsMap}],
        socket_options => case IpVersion of
            ipv4 -> [];
            ipv6 -> [inet6]
        end
    },
    Options2 = case Password of
        {some, Pw} -> maps:put(password, Pw, Options1);
        none -> Options1
    end,
    pgo_pool:start_link(PoolName, Options2).

query(Pool, Sql, Arguments, Timeout) ->
    Res = case Pool of
        {single_connection, Conn} ->
            pgo_handler:extended_query(
                Conn, Sql, Arguments, #{queue_time => undefined}
            );
        {pool, Name} ->
            Options = #{
                pool => Name,
                pool_options => [{timeout, Timeout}]
            },
            pgo:query(Sql, Arguments, Options)
    end,
    case Res of
        #{rows := Rows, num_rows := NumRows} ->
            {ok, {NumRows, Rows}};

        {error, Error} ->
            {error, convert_error(Error)}
    end.

query_extended(Conn, Sql) ->
    case pgo_handler:extended_query(Conn, Sql, [], #{queue_time => undefined}) of
        #{rows := Rows, num_rows := NumRows} ->
            {ok, {NumRows, Rows}};

        {error, Error} ->
            {error, convert_error(Error)}
    end.

checkout(Name) when is_atom(Name) ->
    case pgo:checkout(Name) of
        {ok, Ref, Conn} -> {ok, {Ref, Conn}};
        {error, Error} -> {error, convert_error(Error)}
    end.

convert_error(none_available) ->
    connection_unavailable;
convert_error({pgo_protocol, {parameters, Expected, Got}}) ->
    {unexpected_argument_count, Expected, Got};
convert_error({pgsql_error, #{
    message := Message,
    constraint := Constraint,
    detail := Detail
}}) ->
    {constraint_violated, Message, Constraint, Detail};
convert_error({pgsql_error, #{code := Code, message := Message}}) ->
    Constant = case pog:error_code_name(Code) of
        {ok, X} -> X;
        {error, nil} -> <<"unknown">>
    end,
    {postgresql_error, Code, Constant, Message};
convert_error(#{
    error := badarg_encoding,
    type_info := #type_info{name = Expected},
    value := Value
}) ->
    Got = list_to_binary(io_lib:format("~p", [Value])),
    {unexpected_argument_type, Expected, Got};
convert_error(closed) ->
    query_timeout.
