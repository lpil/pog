//// Postgresql client
////
//// Gleam wrapper around pgo library

// TODO: add time things with zone once pgo supports them

import exception
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/process.{type Name, type Pid}
import gleam/erlang/reference.{type Reference}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string
import gleam/time/calendar.{type Date, type TimeOfDay}
import gleam/time/timestamp.{type Timestamp}
import gleam/uri.{Uri}

/// The port that will be used when none is specified.
const default_port: Int = 5432

pub opaque type Connection {
  Pool(Name(Message))
  SingleConnection(SingleConnection)
}

type SingleConnection

pub type Message

/// Create a reference to a pool using the pool's name.
///
/// If no pool has been started using this name then queries using this
/// connection will fail.
///
pub fn named_connection(name: Name(Message)) -> Connection {
  Pool(name)
}

/// The configuration for a pool of connections.
pub type Config {
  Config(
    /// The Erlang name to register the pool with.
    pool_name: Name(Message),
    /// (default: 127.0.0.1): Database server hostname.
    host: String,
    /// (default: 5432): Port the server is listening on.
    port: Int,
    /// Name of database to use.
    database: String,
    /// Username to connect to database as.
    user: String,
    /// Password for the user.
    password: Option(String),
    /// (default: SslDisabled): Whether to use SSL or not.
    ssl: Ssl,
    /// (default: []): List of 2-tuples, where key and value must be binary
    /// strings. You can include any Postgres connection parameter here, such as
    /// `#("application_name", "myappname")` and `#("timezone", "GMT")`.
    connection_parameters: List(#(String, String)),
    /// (default: 1): Number of connections to keep open with the database
    pool_size: Int,
    /// (default: 50) Checking out connections is handled through a queue. If it
    /// takes longer than queue_target to get out of the queue for longer than
    /// queue_interval then the queue_target will be doubled and checkouts will
    /// start to be dropped if that target is surpassed.
    queue_target: Int,
    /// (default: 1000)
    queue_interval: Int,
    /// (default: 1000): The database is pinged every idle_interval when the
    /// connection is idle.
    idle_interval: Int,
    /// trace (default: False): pgo is instrumented with [OpenCensus][1] and
    /// when this option is true a span will be created (if sampled).
    ///
    /// [1]: https://opencensus.io/
    trace: Bool,
    /// (default: Ipv4) Which internet protocol to use for this connection
    ip_version: IpVersion,
    /// (default: False) By default, pgo will return a n-tuple, in the order of the query.
    /// By setting `rows_as_map` to `True`, the result will be `Dict`.
    rows_as_map: Bool,
  )
}

pub type Ssl {
  /// Enable SSL connection, and check CA certificate. It is the most secured
  /// option to use SSL and should be always used by default.
  /// Never ignore CA certificate checking _unless you know exactly what you are
  /// doing_.
  SslVerified
  /// Enable SSL connection, but don't check CA certificate.
  /// `SslVerified` should always be prioritized upon `SslUnverified`.
  /// As it implies, that option enables SSL, but as it is unverified, the
  /// connection can be unsafe. _Use this option only if you know what you're
  /// doing._ In case `pog` can not find the proper CA certificate, take a look
  /// at the README to get some help to inject the CA certificate in your OS.
  SslUnverified
  /// Disable SSL connection completely. Using this option will let the
  /// connection unsecured, and should be avoided in production environment.
  SslDisabled
}

/// Database server hostname.
///
/// (default: 127.0.0.1)
pub fn host(config: Config, host: String) -> Config {
  Config(..config, host:)
}

/// Port the server is listening on.
///
/// (default: 5432)
pub fn port(config: Config, port: Int) -> Config {
  Config(..config, port:)
}

/// Name of database to use.
pub fn database(config: Config, database: String) -> Config {
  Config(..config, database:)
}

/// Username to connect to database as.
pub fn user(config: Config, user: String) -> Config {
  Config(..config, user:)
}

/// Password for the user.
pub fn password(config: Config, password: Option(String)) -> Config {
  Config(..config, password:)
}

/// Whether to use SSL or not.
///
/// (default: False)
pub fn ssl(config: Config, ssl: Ssl) -> Config {
  Config(..config, ssl:)
}

/// Any Postgres connection parameter here, such as
/// `"application_name: myappname"` and `"timezone: GMT"`
pub fn connection_parameter(
  config: Config,
  name name: String,
  value value: String,
) -> Config {
  Config(..config, connection_parameters: [
    #(name, value),
    ..config.connection_parameters
  ])
}

/// Number of connections to keep open with the database
///
/// default: 10
pub fn pool_size(config: Config, pool_size: Int) -> Config {
  Config(..config, pool_size:)
}

/// Checking out connections is handled through a queue. If it
/// takes longer than queue_target to get out of the queue for longer than
/// queue_interval then the queue_target will be doubled and checkouts will
/// start to be dropped if that target is surpassed.
///
/// default: 50
pub fn queue_target(config: Config, queue_target: Int) -> Config {
  Config(..config, queue_target:)
}

/// Checking out connections is handled through a queue. If it
/// takes longer than queue_target to get out of the queue for longer than
/// queue_interval then the queue_target will be doubled and checkouts will
/// start to be dropped if that target is surpassed.
///
/// default: 1000
pub fn queue_interval(config: Config, queue_interval: Int) -> Config {
  Config(..config, queue_interval:)
}

/// The database is pinged every idle_interval when the connection is idle.
///
/// default: 1000
pub fn idle_interval(config: Config, idle_interval: Int) -> Config {
  Config(..config, idle_interval:)
}

/// Trace pgo is instrumented with [OpenTelemetry][1] and
/// when this option is true a span will be created (if sampled).
///
/// default: False
///
/// [1]: https://opentelemetry.io
pub fn trace(config: Config, trace: Bool) -> Config {
  Config(..config, trace:)
}

/// Which internet protocol to use for this connection
pub fn ip_version(config: Config, ip_version: IpVersion) -> Config {
  Config(..config, ip_version:)
}

/// By default, pgo will return a n-tuple, in the order of the query.
/// By setting `rows_as_map` to `True`, the result will be `Dict`.
pub fn rows_as_map(config: Config, rows_as_map: Bool) -> Config {
  Config(..config, rows_as_map:)
}

/// The internet protocol version to use.
pub type IpVersion {
  /// Internet Protocol version 4 (IPv4)
  Ipv4
  /// Internet Protocol version 6 (IPv6)
  Ipv6
}

/// The default configuration for a connection pool, with a single connection.
/// You will likely want to increase the size of the pool for your application.
///
pub fn default_config(pool_name pool_name: Name(Message)) -> Config {
  Config(
    pool_name:,
    host: "127.0.0.1",
    port: default_port,
    database: "postgres",
    user: "postgres",
    password: None,
    ssl: SslDisabled,
    connection_parameters: [],
    pool_size: 10,
    queue_target: 50,
    queue_interval: 1000,
    idle_interval: 1000,
    trace: False,
    ip_version: Ipv4,
    rows_as_map: False,
  )
}

/// Parse a database url into configuration that can be used to start a pool.
pub fn url_config(
  name: Name(Message),
  database_url: String,
) -> Result(Config, Nil) {
  use uri <- result.try(uri.parse(database_url))
  let uri = case uri.port {
    Some(_) -> uri
    None -> Uri(..uri, port: Some(default_port))
  }
  use #(userinfo, host, path, db_port, query) <- result.try(case uri {
    Uri(
      scheme: Some(scheme),
      userinfo: Some(userinfo),
      host: Some(host),
      port: Some(db_port),
      path: path,
      query: query,
      ..,
    ) -> {
      case scheme {
        "postgres" | "postgresql" -> Ok(#(userinfo, host, path, db_port, query))
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  })
  use #(user, password) <- result.try(extract_user_password(userinfo))
  use ssl <- result.try(extract_ssl_mode(query))
  case string.split(path, "/") {
    ["", database] ->
      Ok(
        Config(
          ..default_config(name),
          host: host,
          port: db_port,
          database: database,
          user: user,
          password: password,
          ssl: ssl,
        ),
      )
    _ -> Error(Nil)
  }
}

/// Expects `userinfo` as `"username"` or `"username:password"`. Fails otherwise.
fn extract_user_password(
  userinfo: String,
) -> Result(#(String, Option(String)), Nil) {
  case string.split(userinfo, ":") {
    [user] -> Ok(#(user, None))
    [user, password] -> Ok(#(user, Some(password)))
    _ -> Error(Nil)
  }
}

/// Expects `sslmode` to be `require`, `verify-ca`, `verify-full` or `disable`.
///
/// If `sslmode` is set, but not one of those value, fails.
///
/// If `sslmode` is `verify-ca` or `verify-full`, returns `SslVerified`.
///
/// If `sslmode` is `require`, returns `SslUnverified`.
///
/// If `sslmode` is unset, returns `SslDisabled`.
///
fn extract_ssl_mode(query: option.Option(String)) -> Result(Ssl, Nil) {
  case query {
    option.None -> Ok(SslDisabled)
    option.Some(query) -> {
      use query <- result.try(uri.parse_query(query))
      use sslmode <- result.try(list.key_find(query, "sslmode"))
      case sslmode {
        "require" -> Ok(SslUnverified)
        "verify-ca" | "verify-full" -> Ok(SslVerified)
        "disable" -> Ok(SslDisabled)
        _ -> Error(Nil)
      }
    }
  }
}

/// Start a database connection pool. Most the time you want to use
/// `supervised` and add the pool to your supervision tree instead of using this
/// function directly.
///
/// The pool is started in a new process and will asynchronously connect to the
/// PostgreSQL instance specified in the config. If the configuration is invalid
/// or it cannot connect for another reason it will continue to attempt to
/// connect, and any queries made using the connection pool will fail.
///
pub fn start(config: Config) -> actor.StartResult(Connection) {
  case start_tree(config) {
    Ok(pid) -> Ok(actor.Started(pid, Pool(config.pool_name)))
    Error(reason) -> Error(actor.InitExited(process.Abnormal(reason)))
  }
}

@external(erlang, "pog_ffi", "start")
fn start_tree(config: Config) -> Result(Pid, dynamic.Dynamic)

/// Start a database connection pool by adding it to your supervision tree.
///
/// Use the `named_connection` function to create a connection to query this
/// pool with if your supervisor does not pass back the return value of
/// creating the pool.
///
/// The pool is started in a new process and will asynchronously connect to the
/// PostgreSQL instance specified in the config. If the configuration is invalid
/// or it cannot connect for another reason it will continue to attempt to
/// connect, and any queries made using the connection pool will fail.
///
pub fn supervised(config: Config) -> supervision.ChildSpecification(Connection) {
  supervision.supervisor(fn() { start(config) })
}

/// A value that can be sent to PostgreSQL as one of the arguments to a
/// parameterised SQL query.
pub type Value

@external(erlang, "pog_ffi", "null")
pub fn null() -> Value

@external(erlang, "pog_ffi", "coerce")
pub fn bool(a: Bool) -> Value

@external(erlang, "pog_ffi", "coerce")
pub fn int(a: Int) -> Value

@external(erlang, "pog_ffi", "coerce")
pub fn float(a: Float) -> Value

@external(erlang, "pog_ffi", "coerce")
pub fn text(a: String) -> Value

@external(erlang, "pog_ffi", "coerce")
pub fn bytea(a: BitArray) -> Value

pub fn array(converter: fn(a) -> Value, values: List(a)) -> Value {
  list.map(values, converter)
  |> coerce_value
}

pub fn timestamp(timestamp: Timestamp) -> Value {
  let #(seconds, nanoseconds) =
    timestamp.to_unix_seconds_and_nanoseconds(timestamp)
  coerce_value(seconds * 1_000_000 + nanoseconds / 1000)
}

pub fn timestamp_decoder() -> decode.Decoder(Timestamp) {
  use microseconds <- decode.map(decode.int)
  let seconds = microseconds / 1_000_000
  let nanoseconds = { microseconds % 1_000_000 } * 1000
  timestamp.from_unix_seconds_and_nanoseconds(seconds, nanoseconds)
}

pub fn calendar_date(date: Date) -> Value {
  let month = calendar.month_to_int(date.month)
  coerce_value(#(date.year, month, date.day))
}

pub fn calendar_time_of_day(time: TimeOfDay) -> Value {
  let seconds = int.to_float(time.seconds)
  let seconds = seconds +. int.to_float(time.nanoseconds) /. 1_000_000_000.0
  coerce_value(#(time.hours, time.minutes, seconds))
}

@external(erlang, "pog_ffi", "coerce")
fn coerce_value(a: anything) -> Value

pub type TransactionError(error) {
  TransactionQueryError(QueryError)
  TransactionRolledBack(error)
}

/// Runs a function within a PostgreSQL transaction.
///
/// If the function returns an `Ok` then the transaction is committed.
///
/// If the function returns an `Error` or panics then the transaction is rolled
/// back.
pub fn transaction(
  pool: Connection,
  callback: fn(Connection) -> Result(t, error),
) -> Result(t, TransactionError(error)) {
  case pool {
    SingleConnection(conn) -> {
      transaction_layer(conn, callback)
    }
    Pool(name) -> {
      // Check out a single connection from the pool
      use #(ref, conn) <- result.try(
        checkout(name) |> result.map_error(TransactionQueryError),
      )

      // Make a best attempt to check back in the connection, even if this
      // process crashes
      use <- exception.defer(fn() { checkin(ref, conn) })

      transaction_layer(conn, callback)
    }
  }
}

fn transaction_layer(
  conn: SingleConnection,
  callback: fn(Connection) -> Result(t, error),
) -> Result(t, TransactionError(error)) {
  let do = fn(conn, sql) {
    run_query_extended(conn, sql)
    |> result.map_error(TransactionQueryError)
  }

  // Start a transaction with the single connection
  use _ <- result.try(do(conn, "begin"))

  // When the callback crashes we want to roll back the transaction
  use <- exception.on_crash(fn() {
    let assert Ok(_) = do(conn, "rollback") as "rollback exec failed"
  })

  case callback(SingleConnection(conn)) {
    // The callback was OK, commit the transaction
    Ok(t) -> {
      use _ <- result.try(do(conn, "commit"))
      Ok(t)
    }

    Error(error) -> {
      // The callback failed, roll-back the transaction
      use _ <- result.try(do(conn, "rollback"))
      Error(TransactionRolledBack(error))
    }
  }
}

@external(erlang, "pog_ffi", "checkout")
fn checkout(
  pool: Name(Message),
) -> Result(#(Reference, SingleConnection), QueryError)

@external(erlang, "pgo", "checkin")
fn checkin(ref: Reference, conn: SingleConnection) -> Dynamic

pub fn nullable(inner_type: fn(a) -> Value, value: Option(a)) -> Value {
  case value {
    Some(term) -> inner_type(term)
    None -> null()
  }
}

/// The rows and number of rows that are returned by a database query.
pub type Returned(t) {
  Returned(count: Int, rows: List(t))
}

@external(erlang, "pog_ffi", "query")
fn run_query(
  a: Connection,
  b: String,
  c: List(Value),
  timeout: Int,
) -> Result(#(Int, List(Dynamic)), QueryError)

@external(erlang, "pog_ffi", "query_extended")
fn run_query_extended(
  connection: SingleConnection,
  query: String,
) -> Result(#(Int, List(Dynamic)), QueryError)

pub type QueryError {
  /// The query failed as a database constraint would have been violated by the
  /// change.
  ConstraintViolated(message: String, constraint: String, detail: String)
  /// The query failed within the database.
  /// https://www.postgresql.org/docs/current/errcodes-appendix.html
  PostgresqlError(code: String, name: String, message: String)
  // The number of arguments supplied did not match the number of parameters
  // that the query has.
  UnexpectedArgumentCount(expected: Int, got: Int)
  /// One of the arguments supplied was not of the type that the query required.
  UnexpectedArgumentType(expected: String, got: String)
  /// The rows returned by the database could not be decoded using the supplied
  /// dynamic decoder.
  UnexpectedResultType(List(decode.DecodeError))
  /// The query timed out.
  QueryTimeout
  /// No connection was available to execute the query. This may be due to
  /// invalid connection details such as an invalid username or password.
  ConnectionUnavailable
}

pub opaque type Query(row_type) {
  Query(
    sql: String,
    parameters: List(Value),
    row_decoder: Decoder(row_type),
    timeout: Int,
  )
}

/// Create a new query to use with the `execute`, `returning`, and `parameter`
/// functions.
///
pub fn query(sql: String) -> Query(Nil) {
  Query(sql:, parameters: [], row_decoder: decode.success(Nil), timeout: 5000)
}

/// Set the decoder to use for the type of row returned by executing this
/// query.
///
/// If the decoder is unable to decode the row value then the query will return
/// an error from the `exec` function, but the query will still have been run
/// against the database.
///
pub fn returning(query: Query(t1), decoder: Decoder(t2)) -> Query(t2) {
  let Query(sql:, parameters:, row_decoder: _, timeout:) = query
  Query(sql:, parameters:, row_decoder: decoder, timeout:)
}

/// Push a new query parameter value for the query.
pub fn parameter(query: Query(t1), parameter: Value) -> Query(t1) {
  Query(..query, parameters: [parameter, ..query.parameters])
}

/// Use a custom timeout for the query, in milliseconds.
/// the default connection timeout.
///
/// If this function is not used to give a timeout then default of 5000 ms is
/// used.
///
pub fn timeout(query: Query(t1), timeout: Int) -> Query(t1) {
  Query(..query, timeout:)
}

/// Run a query against a PostgreSQL database.
///
pub fn execute(
  query query: Query(t),
  on pool: Connection,
) -> Result(Returned(t), QueryError) {
  let parameters = list.reverse(query.parameters)
  use #(count, rows) <- result.try(run_query(
    pool,
    query.sql,
    parameters,
    query.timeout,
  ))
  use rows <- result.try(
    list.try_map(over: rows, with: decode.run(_, query.row_decoder))
    |> result.map_error(UnexpectedResultType),
  )
  Ok(Returned(count, rows))
}

/// Get the name for a PostgreSQL error code.
///
/// ```gleam
/// > error_code_name("01007")
/// Ok("privilege_not_granted")
/// ```
///
/// https://www.postgresql.org/docs/current/errcodes-appendix.html
pub fn error_code_name(error_code: String) -> Result(String, Nil) {
  case error_code {
    "00000" -> Ok("successful_completion")
    "01000" -> Ok("warning")
    "0100C" -> Ok("dynamic_result_sets_returned")
    "01008" -> Ok("implicit_zero_bit_padding")
    "01003" -> Ok("null_value_eliminated_in_set_function")
    "01007" -> Ok("privilege_not_granted")
    "01006" -> Ok("privilege_not_revoked")
    "01004" -> Ok("string_data_right_truncation")
    "01P01" -> Ok("deprecated_feature")
    "02000" -> Ok("no_data")
    "02001" -> Ok("no_additional_dynamic_result_sets_returned")
    "03000" -> Ok("sql_statement_not_yet_complete")
    "08000" -> Ok("connection_exception")
    "08003" -> Ok("connection_does_not_exist")
    "08006" -> Ok("connection_failure")
    "08001" -> Ok("sqlclient_unable_to_establish_sqlconnection")
    "08004" -> Ok("sqlserver_rejected_establishment_of_sqlconnection")
    "08007" -> Ok("transaction_resolution_unknown")
    "08P01" -> Ok("protocol_violation")
    "09000" -> Ok("triggered_action_exception")
    "0A000" -> Ok("feature_not_supported")
    "0B000" -> Ok("invalid_transaction_initiation")
    "0F000" -> Ok("locator_exception")
    "0F001" -> Ok("invalid_locator_specification")
    "0L000" -> Ok("invalid_grantor")
    "0LP01" -> Ok("invalid_grant_operation")
    "0P000" -> Ok("invalid_role_specification")
    "0Z000" -> Ok("diagnostics_exception")
    "0Z002" -> Ok("stacked_diagnostics_accessed_without_active_handler")
    "20000" -> Ok("case_not_found")
    "21000" -> Ok("cardinality_violation")
    "22000" -> Ok("data_exception")
    "2202E" -> Ok("array_subscript_error")
    "22021" -> Ok("character_not_in_repertoire")
    "22008" -> Ok("datetime_field_overflow")
    "22012" -> Ok("division_by_zero")
    "22005" -> Ok("error_in_assignment")
    "2200B" -> Ok("escape_character_conflict")
    "22022" -> Ok("indicator_overflow")
    "22015" -> Ok("interval_field_overflow")
    "2201E" -> Ok("invalid_argument_for_logarithm")
    "22014" -> Ok("invalid_argument_for_ntile_function")
    "22016" -> Ok("invalid_argument_for_nth_value_function")
    "2201F" -> Ok("invalid_argument_for_power_function")
    "2201G" -> Ok("invalid_argument_for_width_bucket_function")
    "22018" -> Ok("invalid_character_value_for_cast")
    "22007" -> Ok("invalid_datetime_format")
    "22019" -> Ok("invalid_escape_character")
    "2200D" -> Ok("invalid_escape_octet")
    "22025" -> Ok("invalid_escape_sequence")
    "22P06" -> Ok("nonstandard_use_of_escape_character")
    "22010" -> Ok("invalid_indicator_parameter_value")
    "22023" -> Ok("invalid_parameter_value")
    "22013" -> Ok("invalid_preceding_or_following_size")
    "2201B" -> Ok("invalid_regular_expression")
    "2201W" -> Ok("invalid_row_count_in_limit_clause")
    "2201X" -> Ok("invalid_row_count_in_result_offset_clause")
    "2202H" -> Ok("invalid_tablesample_argument")
    "2202G" -> Ok("invalid_tablesample_repeat")
    "22009" -> Ok("invalid_time_zone_displacement_value")
    "2200C" -> Ok("invalid_use_of_escape_character")
    "2200G" -> Ok("most_specific_type_mismatch")
    "22004" -> Ok("null_value_not_allowed")
    "22002" -> Ok("null_value_no_indicator_parameter")
    "22003" -> Ok("numeric_value_out_of_range")
    "2200H" -> Ok("sequence_generator_limit_exceeded")
    "22026" -> Ok("string_data_length_mismatch")
    "22001" -> Ok("string_data_right_truncation")
    "22011" -> Ok("substring_error")
    "22027" -> Ok("trim_error")
    "22024" -> Ok("unterminated_c_string")
    "2200F" -> Ok("zero_length_character_string")
    "22P01" -> Ok("floating_point_exception")
    "22P02" -> Ok("invalid_text_representation")
    "22P03" -> Ok("invalid_binary_representation")
    "22P04" -> Ok("bad_copy_file_format")
    "22P05" -> Ok("untranslatable_character")
    "2200L" -> Ok("not_an_xml_document")
    "2200M" -> Ok("invalid_xml_document")
    "2200N" -> Ok("invalid_xml_content")
    "2200S" -> Ok("invalid_xml_comment")
    "2200T" -> Ok("invalid_xml_processing_instruction")
    "22030" -> Ok("duplicate_json_object_key_value")
    "22031" -> Ok("invalid_argument_for_sql_json_datetime_function")
    "22032" -> Ok("invalid_json_text")
    "22033" -> Ok("invalid_sql_json_subscript")
    "22034" -> Ok("more_than_one_sql_json_item")
    "22035" -> Ok("no_sql_json_item")
    "22036" -> Ok("non_numeric_sql_json_item")
    "22037" -> Ok("non_unique_keys_in_a_json_object")
    "22038" -> Ok("singleton_sql_json_item_required")
    "22039" -> Ok("sql_json_array_not_found")
    "2203A" -> Ok("sql_json_member_not_found")
    "2203B" -> Ok("sql_json_number_not_found")
    "2203C" -> Ok("sql_json_object_not_found")
    "2203D" -> Ok("too_many_json_array_elements")
    "2203E" -> Ok("too_many_json_object_members")
    "2203F" -> Ok("sql_json_scalar_required")
    "23000" -> Ok("integrity_constraint_violation")
    "23001" -> Ok("restrict_violation")
    "23502" -> Ok("not_null_violation")
    "23503" -> Ok("foreign_key_violation")
    "23505" -> Ok("unique_violation")
    "23514" -> Ok("check_violation")
    "23P01" -> Ok("exclusion_violation")
    "24000" -> Ok("invalid_cursor_state")
    "25000" -> Ok("invalid_transaction_state")
    "25001" -> Ok("active_sql_transaction")
    "25002" -> Ok("branch_transaction_already_active")
    "25008" -> Ok("held_cursor_requires_same_isolation_level")
    "25003" -> Ok("inappropriate_access_mode_for_branch_transaction")
    "25004" -> Ok("inappropriate_isolation_level_for_branch_transaction")
    "25005" -> Ok("no_active_sql_transaction_for_branch_transaction")
    "25006" -> Ok("read_only_sql_transaction")
    "25007" -> Ok("schema_and_data_statement_mixing_not_supported")
    "25P01" -> Ok("no_active_sql_transaction")
    "25P02" -> Ok("in_failed_sql_transaction")
    "25P03" -> Ok("idle_in_transaction_session_timeout")
    "26000" -> Ok("invalid_sql_statement_name")
    "27000" -> Ok("triggered_data_change_violation")
    "28000" -> Ok("invalid_authorization_specification")
    "28P01" -> Ok("invalid_password")
    "2B000" -> Ok("dependent_privilege_descriptors_still_exist")
    "2BP01" -> Ok("dependent_objects_still_exist")
    "2D000" -> Ok("invalid_transaction_termination")
    "2F000" -> Ok("sql_routine_exception")
    "2F005" -> Ok("function_executed_no_return_statement")
    "2F002" -> Ok("modifying_sql_data_not_permitted")
    "2F003" -> Ok("prohibited_sql_statement_attempted")
    "2F004" -> Ok("reading_sql_data_not_permitted")
    "34000" -> Ok("invalid_cursor_name")
    "38000" -> Ok("external_routine_exception")
    "38001" -> Ok("containing_sql_not_permitted")
    "38002" -> Ok("modifying_sql_data_not_permitted")
    "38003" -> Ok("prohibited_sql_statement_attempted")
    "38004" -> Ok("reading_sql_data_not_permitted")
    "39000" -> Ok("external_routine_invocation_exception")
    "39001" -> Ok("invalid_sqlstate_returned")
    "39004" -> Ok("null_value_not_allowed")
    "39P01" -> Ok("trigger_protocol_violated")
    "39P02" -> Ok("srf_protocol_violated")
    "39P03" -> Ok("event_trigger_protocol_violated")
    "3B000" -> Ok("savepoint_exception")
    "3B001" -> Ok("invalid_savepoint_specification")
    "3D000" -> Ok("invalid_catalog_name")
    "3F000" -> Ok("invalid_schema_name")
    "40000" -> Ok("transaction_rollback")
    "40002" -> Ok("transaction_integrity_constraint_violation")
    "40001" -> Ok("serialization_failure")
    "40003" -> Ok("statement_completion_unknown")
    "40P01" -> Ok("deadlock_detected")
    "42000" -> Ok("syntax_error_or_access_rule_violation")
    "42601" -> Ok("syntax_error")
    "42501" -> Ok("insufficient_privilege")
    "42846" -> Ok("cannot_coerce")
    "42803" -> Ok("grouping_error")
    "42P20" -> Ok("windowing_error")
    "42P19" -> Ok("invalid_recursion")
    "42830" -> Ok("invalid_foreign_key")
    "42602" -> Ok("invalid_name")
    "42622" -> Ok("name_too_long")
    "42939" -> Ok("reserved_name")
    "42804" -> Ok("datatype_mismatch")
    "42P18" -> Ok("indeterminate_datatype")
    "42P21" -> Ok("collation_mismatch")
    "42P22" -> Ok("indeterminate_collation")
    "42809" -> Ok("wrong_object_type")
    "428C9" -> Ok("generated_always")
    "42703" -> Ok("undefined_column")
    "42883" -> Ok("undefined_function")
    "42P01" -> Ok("undefined_table")
    "42P02" -> Ok("undefined_parameter")
    "42704" -> Ok("undefined_object")
    "42701" -> Ok("duplicate_column")
    "42P03" -> Ok("duplicate_cursor")
    "42P04" -> Ok("duplicate_database")
    "42723" -> Ok("duplicate_function")
    "42P05" -> Ok("duplicate_prepared_statement")
    "42P06" -> Ok("duplicate_schema")
    "42P07" -> Ok("duplicate_table")
    "42712" -> Ok("duplicate_alias")
    "42710" -> Ok("duplicate_object")
    "42702" -> Ok("ambiguous_column")
    "42725" -> Ok("ambiguous_function")
    "42P08" -> Ok("ambiguous_parameter")
    "42P09" -> Ok("ambiguous_alias")
    "42P10" -> Ok("invalid_column_reference")
    "42611" -> Ok("invalid_column_definition")
    "42P11" -> Ok("invalid_cursor_definition")
    "42P12" -> Ok("invalid_database_definition")
    "42P13" -> Ok("invalid_function_definition")
    "42P14" -> Ok("invalid_prepared_statement_definition")
    "42P15" -> Ok("invalid_schema_definition")
    "42P16" -> Ok("invalid_table_definition")
    "42P17" -> Ok("invalid_object_definition")
    "44000" -> Ok("with_check_option_violation")
    "53000" -> Ok("insufficient_resources")
    "53100" -> Ok("disk_full")
    "53200" -> Ok("out_of_memory")
    "53300" -> Ok("too_many_connections")
    "53400" -> Ok("configuration_limit_exceeded")
    "54000" -> Ok("program_limit_exceeded")
    "54001" -> Ok("statement_too_complex")
    "54011" -> Ok("too_many_columns")
    "54023" -> Ok("too_many_arguments")
    "55000" -> Ok("object_not_in_prerequisite_state")
    "55006" -> Ok("object_in_use")
    "55P02" -> Ok("cant_change_runtime_param")
    "55P03" -> Ok("lock_not_available")
    "55P04" -> Ok("unsafe_new_enum_value_usage")
    "57000" -> Ok("operator_intervention")
    "57014" -> Ok("query_canceled")
    "57P01" -> Ok("admin_shutdown")
    "57P02" -> Ok("crash_shutdown")
    "57P03" -> Ok("cannot_connect_now")
    "57P04" -> Ok("database_dropped")
    "57P05" -> Ok("idle_session_timeout")
    "58000" -> Ok("system_error")
    "58030" -> Ok("io_error")
    "58P01" -> Ok("undefined_file")
    "58P02" -> Ok("duplicate_file")
    "72000" -> Ok("snapshot_too_old")
    "F0000" -> Ok("config_file_error")
    "F0001" -> Ok("lock_file_exists")
    "HV000" -> Ok("fdw_error")
    "HV005" -> Ok("fdw_column_name_not_found")
    "HV002" -> Ok("fdw_dynamic_parameter_value_needed")
    "HV010" -> Ok("fdw_function_sequence_error")
    "HV021" -> Ok("fdw_inconsistent_descriptor_information")
    "HV024" -> Ok("fdw_invalid_attribute_value")
    "HV007" -> Ok("fdw_invalid_column_name")
    "HV008" -> Ok("fdw_invalid_column_number")
    "HV004" -> Ok("fdw_invalid_data_type")
    "HV006" -> Ok("fdw_invalid_data_type_descriptors")
    "HV091" -> Ok("fdw_invalid_descriptor_field_identifier")
    "HV00B" -> Ok("fdw_invalid_handle")
    "HV00C" -> Ok("fdw_invalid_option_index")
    "HV00D" -> Ok("fdw_invalid_option_name")
    "HV090" -> Ok("fdw_invalid_string_length_or_buffer_length")
    "HV00A" -> Ok("fdw_invalid_string_format")
    "HV009" -> Ok("fdw_invalid_use_of_null_pointer")
    "HV014" -> Ok("fdw_too_many_handles")
    "HV001" -> Ok("fdw_out_of_memory")
    "HV00P" -> Ok("fdw_no_schemas")
    "HV00J" -> Ok("fdw_option_name_not_found")
    "HV00K" -> Ok("fdw_reply_handle")
    "HV00Q" -> Ok("fdw_schema_not_found")
    "HV00R" -> Ok("fdw_table_not_found")
    "HV00L" -> Ok("fdw_unable_to_create_execution")
    "HV00M" -> Ok("fdw_unable_to_create_reply")
    "HV00N" -> Ok("fdw_unable_to_establish_connection")
    "P0000" -> Ok("plpgsql_error")
    "P0001" -> Ok("raise_exception")
    "P0002" -> Ok("no_data_found")
    "P0003" -> Ok("too_many_rows")
    "P0004" -> Ok("assert_failure")
    "XX000" -> Ok("internal_error")
    "XX001" -> Ok("data_corrupted")
    "XX002" -> Ok("index_corrupted")
    _ -> Error(Nil)
  }
}

pub fn calendar_date_decoder() -> decode.Decoder(Date) {
  use year <- decode.field(0, decode.int)
  use month <- decode.field(1, decode.int)
  use day <- decode.field(2, decode.int)
  case calendar.month_from_int(month) {
    Ok(month) -> decode.success(calendar.Date(year:, month:, day:))
    Error(_) -> decode.failure(calendar.Date(0, calendar.January, 1), "Calendar date")
  }
}

pub fn calendar_time_of_day_decoder() -> decode.Decoder(TimeOfDay) {
  use hours <- decode.field(0, decode.int)
  use minutes <- decode.field(1, decode.int)
  use #(seconds, nanoseconds) <- decode.field(2, seconds_decoder())
  decode.success(calendar.TimeOfDay(hours:, minutes:, seconds:, nanoseconds:))
}

fn seconds_decoder() -> decode.Decoder(#(Int, Int)) {
  let int = {
    decode.int
    |> decode.map(fn(i) { #(i, 0) })
  }
  let float = {
    decode.float
    |> decode.map(fn(f) {
      let floored = float.floor(f)
      let seconds = float.round(floored)
      let microseconds = float.round({ f -. floored } *. 1_000_000_000.0)
      #(seconds, microseconds)
    })
  }
  decode.one_of(int, [float])
}
