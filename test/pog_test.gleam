import exception
import gleam/dynamic/decode.{type Decoder}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import pog

pub fn main() {
  gleeunit.main()
}

pub type Timeout(a) {
  Timeout(time: Int, next: fn() -> a)
}

pub fn run_with_timeout(time: Int, next: fn() -> a) {
  Timeout(time, next)
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

pub fn url_config_no_port_test() {
  let expected =
    pog.default_config()
    |> pog.host("db.test")
    |> pog.port(5432)
    |> pog.database("my_db")
    |> pog.user("u")
    |> pog.password(None)
  pog.url_config("postgres://u@db.test/my_db")
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
    |> pog.returning(decode.at([0], decode.string))
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
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(db)

  let assert Ok(returned) =
    pog.query("SELECT * FROM cats WHERE id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.returning({
      use x0 <- decode.field(0, decode.int)
      use x1 <- decode.field(1, decode.string)
      use x2 <- decode.field(2, decode.bool)
      use x3 <- decode.field(3, decode.list(decode.string))
      use x4 <- decode.field(4, pog.timestamp_decoder())
      use x5 <- decode.field(5, pog.date_decoder())
      decode.success(#(x0, x1, x2, x3, x4, x5))
    })
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
  |> pog.returning(decode.at([0], decoder))
  |> pog.execute(db)
  |> should.equal(Ok(pog.Returned(count: 1, rows: [value])))
  db
}

pub fn null_test() {
  let db = start_default()
  pog.query("select $1")
  |> pog.parameter(pog.null())
  |> pog.returning(decode.at([0], decode.optional(decode.int)))
  |> pog.execute(db)
  |> should.equal(Ok(pog.Returned(count: 1, rows: [None])))

  pog.disconnect(db)
}

pub fn bool_test() {
  start_default()
  |> assert_roundtrip(True, "bool", pog.bool, decode.bool)
  |> assert_roundtrip(False, "bool", pog.bool, decode.bool)
  |> pog.disconnect
}

pub fn int_test() {
  start_default()
  |> assert_roundtrip(0, "int", pog.int, decode.int)
  |> assert_roundtrip(1, "int", pog.int, decode.int)
  |> assert_roundtrip(2, "int", pog.int, decode.int)
  |> assert_roundtrip(3, "int", pog.int, decode.int)
  |> assert_roundtrip(4, "int", pog.int, decode.int)
  |> assert_roundtrip(5, "int", pog.int, decode.int)
  |> assert_roundtrip(-0, "int", pog.int, decode.int)
  |> assert_roundtrip(-1, "int", pog.int, decode.int)
  |> assert_roundtrip(-2, "int", pog.int, decode.int)
  |> assert_roundtrip(-3, "int", pog.int, decode.int)
  |> assert_roundtrip(-4, "int", pog.int, decode.int)
  |> assert_roundtrip(-5, "int", pog.int, decode.int)
  |> assert_roundtrip(10_000_000, "int", pog.int, decode.int)
  |> pog.disconnect
}

pub fn float_test() {
  start_default()
  |> assert_roundtrip(0.123, "float", pog.float, decode.float)
  |> assert_roundtrip(1.123, "float", pog.float, decode.float)
  |> assert_roundtrip(2.123, "float", pog.float, decode.float)
  |> assert_roundtrip(3.123, "float", pog.float, decode.float)
  |> assert_roundtrip(4.123, "float", pog.float, decode.float)
  |> assert_roundtrip(5.123, "float", pog.float, decode.float)
  |> assert_roundtrip(-0.654, "float", pog.float, decode.float)
  |> assert_roundtrip(-1.654, "float", pog.float, decode.float)
  |> assert_roundtrip(-2.654, "float", pog.float, decode.float)
  |> assert_roundtrip(-3.654, "float", pog.float, decode.float)
  |> assert_roundtrip(-4.654, "float", pog.float, decode.float)
  |> assert_roundtrip(-5.654, "float", pog.float, decode.float)
  |> assert_roundtrip(10_000_000.0, "float", pog.float, decode.float)
  |> pog.disconnect
}

pub fn text_test() {
  start_default()
  |> assert_roundtrip("", "text", pog.text, decode.string)
  |> assert_roundtrip("✨", "text", pog.text, decode.string)
  |> assert_roundtrip("Hello, Joe!", "text", pog.text, decode.string)
  |> pog.disconnect
}

pub fn bytea_test() {
  start_default()
  |> assert_roundtrip(<<"":utf8>>, "bytea", pog.bytea, decode.bit_array)
  |> assert_roundtrip(<<"✨":utf8>>, "bytea", pog.bytea, decode.bit_array)
  |> assert_roundtrip(
    <<"Hello, Joe!":utf8>>,
    "bytea",
    pog.bytea,
    decode.bit_array,
  )
  |> assert_roundtrip(<<1>>, "bytea", pog.bytea, decode.bit_array)
  |> assert_roundtrip(<<1, 2, 3>>, "bytea", pog.bytea, decode.bit_array)
  |> pog.disconnect
}

pub fn array_test() {
  let decoder = decode.list(decode.string)
  start_default()
  |> assert_roundtrip(["black"], "text[]", pog.array(pog.text, _), decoder)
  |> assert_roundtrip(["gray"], "text[]", pog.array(pog.text, _), decoder)
  |> assert_roundtrip(["g", "b"], "text[]", pog.array(pog.text, _), decoder)
  |> assert_roundtrip(
    [1, 2, 3],
    "integer[]",
    pog.array(pog.int, _),
    decode.list(decode.int),
  )
  |> pog.disconnect
}

pub fn datetime_test() {
  start_default()
  |> assert_roundtrip(
    pog.Timestamp(pog.Date(2022, 10, 12), pog.Time(11, 30, 33, 101)),
    "timestamp",
    pog.timestamp,
    pog.timestamp_decoder(),
  )
  |> pog.disconnect
}

pub fn date_test() {
  start_default()
  |> assert_roundtrip(
    pog.Date(2022, 10, 11),
    "date",
    pog.date,
    pog.date_decoder(),
  )
  |> pog.disconnect
}

pub fn nullable_test() {
  start_default()
  |> assert_roundtrip(
    Some("Hello, Joe"),
    "text",
    pog.nullable(pog.text, _),
    decode.optional(decode.string),
  )
  |> assert_roundtrip(
    None,
    "text",
    pog.nullable(pog.text, _),
    decode.optional(decode.string),
  )
  |> assert_roundtrip(
    Some(123),
    "int",
    pog.nullable(pog.int, _),
    decode.optional(decode.int),
  )
  |> assert_roundtrip(
    None,
    "int",
    pog.nullable(pog.int, _),
    decode.optional(decode.int),
  )
  |> pog.disconnect
}

pub fn expected_argument_type_test() {
  let db = start_default()

  pog.query("select $1::int")
  |> pog.returning(decode.at([0], decode.string))
  |> pog.parameter(pog.float(1.2))
  |> pog.execute(db)
  |> should.equal(Error(pog.UnexpectedArgumentType("int4", "1.2")))

  pog.disconnect(db)
}

pub fn expected_return_type_test() {
  let db = start_default()
  pog.query("select 1")
  |> pog.returning(decode.at([0], decode.string))
  |> pog.execute(db)
  |> should.equal(
    Error(
      pog.UnexpectedResultType([
        decode.DecodeError(expected: "String", found: "Int", path: ["0"]),
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
  |> pog.returning(decode.at([0], decode.string))
  |> pog.execute(db)
  |> should.equal(Error(pog.QueryTimeout))

  pog.disconnect(db)
}

pub fn expected_ten_millis_no_timeout_test() {
  use <- run_with_timeout(20)
  let db = start_default()

  pog.query("select sub.ret from (select pg_sleep(0.01), 'OK' as ret) as sub")
  |> pog.timeout(30)
  |> pog.returning(decode.at([0], decode.string))
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
  |> pog.returning(decode.at([0], decode.string))
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
    |> pog.returning(decode.at(["id"], decode.int))
    |> pog.execute(db)

  let assert Ok(returned) =
    pog.query("SELECT * FROM cats WHERE id = $1")
    |> pog.parameter(pog.int(id))
    |> pog.returning({
      use id <- decode.field("id", decode.int)
      use name <- decode.field("name", decode.string)
      use is_cute <- decode.field("is_cute", decode.bool)
      use colors <- decode.field("colors", decode.list(decode.string))
      use last_petted_at <- decode.field(
        "last_petted_at",
        pog.timestamp_decoder(),
      )
      use birthday <- decode.field("birthday", pog.date_decoder())
      decode.success(#(id, name, is_cute, colors, last_petted_at, birthday))
    })
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
  let id_decoder = decode.at([0], decode.int)
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
