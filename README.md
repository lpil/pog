# Pog

A PostgreSQL database client for Gleam, based on [PGO][erlang-pgo].

[erlang-pgo]: https://github.com/erleans/pgo

```gleam
import pog
import gleam/dynamic
import gleeunit/should

pub fn main() {
  // Start a database connection pool.
  // Typically you will want to create one pool for use in your program
  let db =
    pog.default_config()
    |> pog.host("localhost")
    |> pog.database("my_database")
    |> pog.pool_size(15)
    |> pog.connect

  // An SQL statement to run. It takes one int as a parameter
  let sql_query = "
  select
    name, age, colour, friends
  from
    cats
  where
    id = $1"

  // This is the decoder for the value returned by the query
  let row_decoder = dynamic.tuple4(
    dynamic.string,
    dynamic.int,
    dynamic.string,
    dynamic.list(dynamic.string),
  )

  // Run the query against the PostgreSQL database
  // The int `1` is given as a parameter
  let assert Ok(response) =
    pog.query(sql_query)
    |> pog.parameter(pog.int(1))
    |> pog.returning(row_decoder)
    |> pog.execute(db)

  // And then do something with the returned results
  response.count
  |> should.equal(2)
  response.rows
  |> should.equal([
    #("Nubi", 3, "black", ["Al", "Cutlass"]),
  ])
}
```

## Installation

```sh
gleam add pog
```

## Support of connection URI

Configuring a Postgres connection is done by using `Config` type in `pog`.
To facilitate connection, and to provide easy integration with the rest of the
Postgres ecosystem, `pog` provides handling of
[connection URI as defined by Postgres](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING-URIS).
Shape of connection URI is `postgresql://[username:password@][host:port][/dbname][?query]`.
Call `pog.url_config` with your connection URI, and in case it's correct
against the Postgres standard, your `Config` will be automatically generated!

Here's an example, using [`envoy`](https://github.com/lpil/envoy) to read the
connection URI from the environment.

```gleam
import envoy
import pog

/// Read the DATABASE_URL environment variable.
/// Generate the pog.Config from that database URL.
/// Finally, connect to database.
pub fn read_connection_uri() -> Result(pog.Connection, Nil) {
  use database_url <- result.try(envoy.get("DATABASE_URL"))
  use config <- result.try(pog.url_config(database_url))
  Ok(pog.connect(config))
}
```

## About JSON

In Postgres, you can define a type `json` or `jsonb`. Such a type can be query
in SQL, but Postgres returns it a simple string, and accepts it as a simple string!
When writing or reading a JSON, you can simply use
`pog.text(json.to_string(my_json))` and `dynamic.string` to respectively write
and read them!

## Timeout

By default, every pog query has a 5 seconds timeout, and every query taking more
than 5 seconds will automatically be aborted. That behaviour can be changed
through the usage of `default_timeout` or `timeout`. `default_timeout` should be
used on `Config`, and defines the timeout that will be used for every query
using that connection, while `timeout` handles timeout query by query. If you have
one query taking more time than your default timeout to complete, you can override
that behaviour specifically for that one.

## Rows as maps

By default, `pgo` will return every selected value from your query as a tuple.
In case you want a different output, you can activate `rows_as_maps` in `Config`.
Once activated, every returned rows will take the form of a `Dict`.

## Atom generation

Creating a connection pool with the `pog.connect` function dynamically generates
an Erlang atom. Atoms are not garbage collected and only a certain number of
them can exist in an Erlang VM instance, and hitting this limit will result in
the VM crashing. Due to this limitation you should not dynamically open new
connection pools, instead create the pools you need when your application starts
and reuse them throughout the lifetime of your program.

## History

Previously this library was named `gleam_pgo`. This old name is deprecated and
all future development and support will happen here.
