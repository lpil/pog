import exception
import gleam/dynamic.{type Decoder}
import gleam/erlang/atom
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import pog

pub fn main() {
  gleeunit.main()
}

pub fn run_with_timeout(time: Int, next: fn() -> a) {
  let assert Ok(timeout) = atom.from_string("timeout")
  #(timeout, time, next)
}

pub fn url_config_everything_test() {
  let expected =
    pog.default_config()
    |> pog.host("db.test")
    |> pog.port(1234)
    |> pog.database("my_db")
    |> pog.user("u")
    |> pog.password(Some("p"))

  pog.url_config("postgres://u:p@db.test:1234/my_db")
  |> should.equal(Ok(expected))
}

pub fn url_config_alternative_postgres_protocol_test() {
  let expected =
    pog.default_config()
    |> pog.host("db.test")
    |> pog.port(1234)
    |> pog.database("my_db")
    |> pog.user("u")
    |> pog.password(Some("p"))
  pog.url_config("postgresql://u:p@db.test:1234/my_db")
  |> should.equal(Ok(expected))
}

pub fn url_config_not_postgres_protocol_test() {
  pog.url_config("foo://u:p@db.test:1234/my_db")
  |> should.equal(Error(Nil))
}

pub fn url_config_no_password_test() {
  let expected =
    pog.default_config()
    |> pog.host("db.test")
    |> pog.port(1234)
    |> pog.database("my_db")
    |> pog.user("u")
    |> pog.password(None)
  pog.url_config("postgres://u@db.test:1234/my_db")
  |> should.equal(Ok(expected))
}

pub fn url_config_path_slash_test() {
  pog.url_config("postgres://u:p@db.test:1234/my_db/foo")
  |> should.equal(Error(Nil))
}

fn start_default() {
  pog.Config(
    ..pog.default_config(),
    database: "gleam_pog_test",
    password: Some("postgres"),
    pool_size: 1,
  )
  |> pog.connect
}

fn default_config() {
  pog.Config(
    ..pog.default_config(),
    database: "gleam_pog_test",
    password: Some("postgres"),
    pool_size: 1,
  )
}

pub fn inserting_new_rows_test() {
  let db = start_default()
  let sql =
    "
  INSERT INTO
    cats
  VALUES
    (DEFAULT, 'bill', true, ARRAY ['black'], now(), '2020-03-04'),
    (DEFAULT, 'felix', false, ARRAY ['grey'], now(), '2020-03-05')"
  let assert Ok(returned) = pog.query(sql) |> pog.execute(db)

  returned.count
  |> should.equal(2)
  returned.rows
  |> should.equal([])

  pog.disconnect(db)
}

pub fn inserting_new_rows_and_returning_test() {
  let db = start_default()
  let sql =
    "
  INSERT INTO
    cats
  VALUES
    (DEFAULT, 'bill', true, ARRAY ['black'], now(), '2020-03-04'),
    (DEFAULT, 'felix', false, ARRAY ['grey'], now(), '2020-03-05')
  RETURNING
    name"
  let assert Ok(returned) =
    pog.query(sql)
    |> pog.returning(dynamic.element(0, dynamic.string))
    |> pog.execute(db)

  returned.count
  |> should.equal(2)
  returned.rows
  |> should.equal(["bill", "felix"])

  pog.disconnect(db)
}

pub fn selecting_rows_test() {
  let db = start_default()
  let sql =
    "
    INSERT INTO
      cats
    VALUES
      (DEFAULT, 'neo', true, ARRAY ['black'], '2022-10-10 11:30:30.1', '2020-03-04')
    RETURNING
      id"

  let assert Ok(pog.Returned(rows: [id], ..)) =
    pog.query(sql)
    |> pog.returning(dynamic.element(0, dynamic.int))
    |> pog.execute(db)

  let assert Ok(returned) =
    pog.query("SELECT * FROM cats WHERE id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.returning(dynamic.tuple6(
      dynamic.int,
      dynamic.string,
      dynamic.bool,
      dynamic.list(dynamic.string),
      pog.decode_timestamp,
      pog.decode_date,
    ))
    |> pog.execute(db)

  returned.count
  |> should.equal(1)
  returned.rows
  |> should.equal([
    #(
      id,
      "neo",
      True,
      ["black"],
      pog.Timestamp(pog.Date(2022, 10, 10), pog.Time(11, 30, 30, 100_000)),
      pog.Date(2020, 3, 4),
    ),
  ])

  pog.disconnect(db)
}

pub fn invalid_sql_test() {
  let db = start_default()
  let sql = "select       select"

  let assert Error(pog.PostgresqlError(code, name, message)) =
    pog.query(sql) |> pog.execute(db)

  code
  |> should.equal("42601")
  name
  |> should.equal("syntax_error")
  message
  |> should.equal("syntax error at or near \"select\"")

  pog.disconnect(db)
}

pub fn insert_constraint_error_test() {
  let db = start_default()
  let sql =
    "
    INSERT INTO
      cats
    VALUES
      (900, 'bill', true, ARRAY ['black'], now(), '2020-03-04'),
      (900, 'felix', false, ARRAY ['black'], now(), '2020-03-05')"

  let assert Error(pog.ConstraintViolated(message, constraint, detail)) =
    pog.query(sql) |> pog.execute(db)

  constraint
  |> should.equal("cats_pkey")

  detail
  |> should.equal("Key (id)=(900) already exists.")

  message
  |> should.equal(
    "duplicate key value violates unique constraint \"cats_pkey\"",
  )

  pog.disconnect(db)
}

pub fn select_from_unknown_table_test() {
  let db = start_default()
  let sql = "SELECT * FROM unknown"

  let assert Error(pog.PostgresqlError(code, name, message)) =
    pog.query(sql) |> pog.execute(db)

  code
  |> should.equal("42P01")
  name
  |> should.equal("undefined_table")
  message
  |> should.equal("relation \"unknown\" does not exist")

  pog.disconnect(db)
}

pub fn insert_with_incorrect_type_test() {
  let db = start_default()
  let sql =
    "
      INSERT INTO
        cats
      VALUES
        (true, true, true, true)"
  let assert Error(pog.PostgresqlError(code, name, message)) =
    pog.query(sql) |> pog.execute(db)

  code
  |> should.equal("42804")
  name
  |> should.equal("datatype_mismatch")
  message
  |> should.equal(
    "column \"id\" is of type integer but expression is of type boolean",
  )

  pog.disconnect(db)
}

pub fn execute_with_wrong_number_of_arguments_test() {
  let db = start_default()
  let sql = "SELECT * FROM cats WHERE id = $1"

  pog.query(sql)
  |> pog.returning(dynamic.dynamic)
  |> pog.execute(db)
  |> should.equal(Error(pog.UnexpectedArgumentCount(expected: 1, got: 0)))

  pog.disconnect(db)
}

fn assert_roundtrip(
  db: pog.Connection,
  value: a,
  type_name: String,
  encoder: fn(a) -> pog.Value,
  decoder: Decoder(a),
) -> pog.Connection {
  pog.query("select $1::" <> type_name)
  |> pog.parameter(encoder(value))
  |> pog.returning(dynamic.element(0, decoder))
  |> pog.execute(db)
  |> should.equal(Ok(pog.Returned(count: 1, rows: [value])))
  db
}

pub fn null_test() {
  let db = start_default()
  pog.query("select $1")
  |> pog.parameter(pog.null())
  |> pog.returning(dynamic.element(0, dynamic.optional(dynamic.int)))
  |> pog.execute(db)
  |> should.equal(Ok(pog.Returned(count: 1, rows: [None])))

  pog.disconnect(db)
}

pub fn bool_test() {
  start_default()
  |> assert_roundtrip(True, "bool", pog.bool, dynamic.bool)
  |> assert_roundtrip(False, "bool", pog.bool, dynamic.bool)
  |> pog.disconnect
}

pub fn int_test() {
  start_default()
  |> assert_roundtrip(0, "int", pog.int, dynamic.int)
  |> assert_roundtrip(1, "int", pog.int, dynamic.int)
  |> assert_roundtrip(2, "int", pog.int, dynamic.int)
  |> assert_roundtrip(3, "int", pog.int, dynamic.int)
  |> assert_roundtrip(4, "int", pog.int, dynamic.int)
  |> assert_roundtrip(5, "int", pog.int, dynamic.int)
  |> assert_roundtrip(-0, "int", pog.int, dynamic.int)
  |> assert_roundtrip(-1, "int", pog.int, dynamic.int)
  |> assert_roundtrip(-2, "int", pog.int, dynamic.int)
  |> assert_roundtrip(-3, "int", pog.int, dynamic.int)
  |> assert_roundtrip(-4, "int", pog.int, dynamic.int)
  |> assert_roundtrip(-5, "int", pog.int, dynamic.int)
  |> assert_roundtrip(10_000_000, "int", pog.int, dynamic.int)
  |> pog.disconnect
}

pub fn float_test() {
  start_default()
  |> assert_roundtrip(0.123, "float", pog.float, dynamic.float)
  |> assert_roundtrip(1.123, "float", pog.float, dynamic.float)
  |> assert_roundtrip(2.123, "float", pog.float, dynamic.float)
  |> assert_roundtrip(3.123, "float", pog.float, dynamic.float)
  |> assert_roundtrip(4.123, "float", pog.float, dynamic.float)
  |> assert_roundtrip(5.123, "float", pog.float, dynamic.float)
  |> assert_roundtrip(-0.654, "float", pog.float, dynamic.float)
  |> assert_roundtrip(-1.654, "float", pog.float, dynamic.float)
  |> assert_roundtrip(-2.654, "float", pog.float, dynamic.float)
  |> assert_roundtrip(-3.654, "float", pog.float, dynamic.float)
  |> assert_roundtrip(-4.654, "float", pog.float, dynamic.float)
  |> assert_roundtrip(-5.654, "float", pog.float, dynamic.float)
  |> assert_roundtrip(10_000_000.0, "float", pog.float, dynamic.float)
  |> pog.disconnect
}

pub fn text_test() {
  start_default()
  |> assert_roundtrip("", "text", pog.text, dynamic.string)
  |> assert_roundtrip("✨", "text", pog.text, dynamic.string)
  |> assert_roundtrip("Hello, Joe!", "text", pog.text, dynamic.string)
  |> pog.disconnect
}

pub fn bytea_test() {
  start_default()
  |> assert_roundtrip(<<"":utf8>>, "bytea", pog.bytea, dynamic.bit_array)
  |> assert_roundtrip(<<"✨":utf8>>, "bytea", pog.bytea, dynamic.bit_array)
  |> assert_roundtrip(
    <<"Hello, Joe!":utf8>>,
    "bytea",
    pog.bytea,
    dynamic.bit_array,
  )
  |> assert_roundtrip(<<1>>, "bytea", pog.bytea, dynamic.bit_array)
  |> assert_roundtrip(<<1, 2, 3>>, "bytea", pog.bytea, dynamic.bit_array)
  |> pog.disconnect
}

pub fn array_test() {
  let decoder = dynamic.list(dynamic.string)
  start_default()
  |> assert_roundtrip(["black"], "text[]", pog.array(pog.text, _), decoder)
  |> assert_roundtrip(["gray"], "text[]", pog.array(pog.text, _), decoder)
  |> assert_roundtrip(["g", "b"], "text[]", pog.array(pog.text, _), decoder)
  |> assert_roundtrip(
    [1, 2, 3],
    "integer[]",
    pog.array(pog.int, _),
    dynamic.list(dynamic.int),
  )
  |> pog.disconnect
}

pub fn datetime_test() {
  start_default()
  |> assert_roundtrip(
    pog.Timestamp(pog.Date(2022, 10, 12), pog.Time(11, 30, 33, 101)),
    "timestamp",
    pog.timestamp,
    pog.decode_timestamp,
  )
  |> pog.disconnect
}

pub fn date_test() {
  start_default()
  |> assert_roundtrip(pog.Date(2022, 10, 11), "date", pog.date, pog.decode_date)
  |> pog.disconnect
}

pub fn nullable_test() {
  start_default()
  |> assert_roundtrip(
    Some("Hello, Joe"),
    "text",
    pog.nullable(pog.text, _),
    dynamic.optional(dynamic.string),
  )
  |> assert_roundtrip(
    None,
    "text",
    pog.nullable(pog.text, _),
    dynamic.optional(dynamic.string),
  )
  |> assert_roundtrip(
    Some(123),
    "int",
    pog.nullable(pog.int, _),
    dynamic.optional(dynamic.int),
  )
  |> assert_roundtrip(
    None,
    "int",
    pog.nullable(pog.int, _),
    dynamic.optional(dynamic.int),
  )
  |> pog.disconnect
}

pub fn expected_argument_type_test() {
  let db = start_default()

  pog.query("select $1::int")
  |> pog.returning(dynamic.element(0, dynamic.string))
  |> pog.parameter(pog.float(1.2))
  |> pog.execute(db)
  |> should.equal(Error(pog.UnexpectedArgumentType("int4", "1.2")))

  pog.disconnect(db)
}

pub fn expected_return_type_test() {
  let db = start_default()
  pog.query("select 1")
  |> pog.returning(dynamic.element(0, dynamic.string))
  |> pog.execute(db)
  |> should.equal(
    Error(
      pog.UnexpectedResultType([
        dynamic.DecodeError(expected: "String", found: "Int", path: ["0"]),
      ]),
    ),
  )

  pog.disconnect(db)
}

pub fn expected_five_millis_timeout_test() {
  use <- run_with_timeout(20)
  let db = start_default()

  pog.query("select sub.ret from (select pg_sleep(0.05), 'OK' as ret) as sub")
  |> pog.timeout(5)
  |> pog.returning(dynamic.element(0, dynamic.string))
  |> pog.execute(db)
  |> should.equal(Error(pog.QueryTimeout))

  pog.disconnect(db)
}

pub fn expected_ten_millis_no_timeout_test() {
  use <- run_with_timeout(20)
  let db = start_default()

  pog.query("select sub.ret from (select pg_sleep(0.01), 'OK' as ret) as sub")
  |> pog.timeout(30)
  |> pog.returning(dynamic.element(0, dynamic.string))
  |> pog.execute(db)
  |> should.equal(Ok(pog.Returned(1, ["Ok"])))

  pog.disconnect(db)
}

pub fn expected_ten_millis_no_default_timeout_test() {
  use <- run_with_timeout(20)
  let db =
    default_config()
    |> pog.default_timeout(30)
    |> pog.connect

  pog.query("select sub.ret from (select pg_sleep(0.01), 'OK' as ret) as sub")
  |> pog.returning(dynamic.element(0, dynamic.string))
  |> pog.execute(db)
  |> should.equal(Ok(pog.Returned(1, ["Ok"])))

  pog.disconnect(db)
}

pub fn expected_maps_test() {
  let db = pog.Config(..default_config(), rows_as_map: True) |> pog.connect

  let sql =
    "
    INSERT INTO
      cats
    VALUES
      (DEFAULT, 'neo', true, ARRAY ['black'], '2022-10-10 11:30:30', '2020-03-04')
    RETURNING
      id"

  let assert Ok(pog.Returned(rows: [id], ..)) =
    pog.query(sql)
    |> pog.returning(dynamic.field("id", dynamic.int))
    |> pog.execute(db)

  let assert Ok(returned) =
    pog.query("SELECT * FROM cats WHERE id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.returning(dynamic.decode6(
      fn(id, name, is_cute, colors, last_petted_at, birthday) {
        #(id, name, is_cute, colors, last_petted_at, birthday)
      },
      dynamic.field("id", dynamic.int),
      dynamic.field("name", dynamic.string),
      dynamic.field("is_cute", dynamic.bool),
      dynamic.field("colors", dynamic.list(dynamic.string)),
      dynamic.field("last_petted_at", pog.decode_timestamp),
      dynamic.field("birthday", pog.decode_date),
    ))
    |> pog.execute(db)

  returned.count
  |> should.equal(1)
  returned.rows
  |> should.equal([
    #(
      id,
      "neo",
      True,
      ["black"],
      pog.Timestamp(pog.Date(2022, 10, 10), pog.Time(11, 30, 30, 0)),
      pog.Date(2020, 3, 4),
    ),
  ])

  pog.disconnect(db)
}

pub fn transaction_commit_test() {
  let db = start_default()
  let id_decoder = dynamic.element(0, dynamic.int)
  let assert Ok(_) = pog.query("truncate table cats") |> pog.execute(db)

  let insert = fn(db, name) {
    let sql = "
  INSERT INTO
    cats
  VALUES
    (DEFAULT, '" <> name <> "', true, ARRAY ['black'], now(), '2020-03-04')
  RETURNING id"
    let assert Ok(pog.Returned(rows: [id], ..)) =
      pog.query(sql)
      |> pog.returning(id_decoder)
      |> pog.execute(db)
    id
  }

  // A succeeding transaction
  let assert Ok(#(id1, id2)) =
    pog.transaction(db, fn(db) {
      let id1 = insert(db, "one")
      let id2 = insert(db, "two")
      Ok(#(id1, id2))
    })

  // An error returning transaction, it gets rolled back
  let assert Error(pog.TransactionRolledBack("Nah bruv!")) =
    pog.transaction(db, fn(db) {
      let _id1 = insert(db, "two")
      let _id2 = insert(db, "three")
      Error("Nah bruv!")
    })

  // A crashing transaction, it gets rolled back
  let _ =
    exception.rescue(fn() {
      pog.transaction(db, fn(db) {
        let _id1 = insert(db, "four")
        let _id2 = insert(db, "five")
        panic as "testing rollbacks"
      })
    })

  let assert Ok(returned) =
    pog.query("select id from cats order by id")
    |> pog.returning(id_decoder)
    |> pog.execute(db)

  let assert [got1, got2] = returned.rows
  let assert True = id1 == got1
  let assert True = id2 == got2

  pog.disconnect(db)
}
