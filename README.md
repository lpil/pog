# Pog

A PostgreSQL database client for Gleam, based on [PGO][erlang-pgo].

[erlang-pgo]: https://github.com/erleans/pgo

```gleam
gleam add pog@4
```

Add a pool to your OTP supervision tree, before any siblings that will need to
use the database.

Pools are named with a `Name` from `gleam/erlang/process`, so create one
outside of your supervision tree and pass it down to the creation of the pool.

```gleam
import gleam/otp/static_supervisor
import pog

pub fn start_application_supervisor(pool_name: process.Name(pog.Message)) {
  let pool_child = 
    pog.defaut_config(pool_name)
    |> pog.host("localhost")
    |> pog.database("my_database")
    |> pog.pool_size(15)
    |> pog.supervised

  supervisor.new(supervisor.RestForOne)
  |> supervisor.add(pool_child)
  // |> supervisor.add(other)
  // |> supervisor.add(application)
  // |> supervisor.add(children)
  |> supervisor.start
}
```

Then in your application you can use a subject created from that name to make
queries:

```gleam
import pog
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}

pub fn run(db: Subject(pog.Message)) {
  // An SQL statement to run. It takes one int as a parameter
  let sql_query = "
  select
    name, age, colour, friends
  from
    cats
  where
    id = $1"

  // This is the decoder for the value returned by the query
  let row_decoder = {
    use name <- decode.field(0, decode.string)
    use age <- decode.field(1, decode.int)
    use colour <- decode.field(2, decode.string)
    use friends <- decode.field(3, decode.list(decode.string))
    decode.success(#(name, age, colour, friends))
  }

  // Run the query against the PostgreSQL database
  // The int `1` is given as a parameter
  let assert Ok(data) =
    pog.query(sql_query)
    |> pog.parameter(pog.int(1))
    |> pog.returning(row_decoder)
    |> pog.execute(db)

  // And then do something with the returned results
  assert data.count == 2
  assert data.rows == [#("Nubi", 3, "black", ["Al", "Cutlass"])])
}
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
pub fn read_connection_uri(name) -> Result(pog.Config, Nil) {
  use database_url <- result.try(envoy.get("DATABASE_URL"))
  pog.url_config(name, database_url)
}
```

## About JSON

In Postgres, you can define a type `json` or `jsonb`. Such a type can be query
in SQL, but Postgres returns it a simple string, and accepts it as a simple string!
When writing or reading a JSON, you can simply use
`pog.text(json.to_string(my_json))` and `decode.string` to respectively write
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

## SSL

As for the rest of the web, you should try to use SSL connections with any
Postgres database. Most of the time, managed instances of Postgres will even
require the library to use SSL connections.

`pog` supports SSL connections out-of-the-box, and stick with current Postgres
conventions to ensure portability of Postgres configuration across ecosystems.

### Postgres SSL conventions

Postgres supports 3 main modes of SSL: SSL disabled, SSL enabled, and SSL
enabled with active security measures (i.e. checking of system-wide CA
certificates). Those modes can be found directly in `psql` client, but also in
most Postgres clients in different languages.

> [!NOTE]
> It could seems weird to have three different modes of SSL, while we usually
> think of SSL a switch: it's turned off, or turned on. When SSL is off, clients
> will simply ignore SSL certificates, and proceed with the connection in an
> unsecured way (as long as the server agrees with unsecure connection). When
> SSL is on, clients will read SSL certificates, and check that the connection
> uses a correct SSL certificates. It will read global Certificates Authority
> and will check that your connection is secured with one of those certificates.
> If we take the browser analogy, SSL turned off is when you're browsing an HTTP
> website, while SSL turned on is when you're browsing an HTTPS website.
> But there's a hidden mode of SSL, where SSL is enabled, but not actively
> checking that the connection is valid. In simple terms, it means the connection
> can be compromised, and the client will not check for Certificates Authority.
> You'll use the SSL connection thinking you are secured, but some potential
> attackers can target you. Continuing the browser analogy, it's when you are
> on a website secured by HTTPS, but the browser will show a warning page saying
> "Impossible to check the validity of certificate.", and you have to click on
> "Continue anyway". When you click on that button, you're using that third mode
> of SSL: it's secured, but you can not be certain that the connection is legit!

In Postgres, conventions used, including in connection URI are as follow:

- Flag used to indicate SSL state is named `sslmode`.
- `disable` disables SSL connection.
- `require` enables SSL connection, but does not check CA certificates.
- `verify-ca` or `verify-full` enables SSL connection, and check for CA certificates.

### `pog` SSL usage

In `pog`, setting up an SSL connection simply ask you to indicate the proper flag
in `pog.Config`. The different options are `SslDisabled`, `SslUnverified` &
`SslVerified`. Because of the nature of the 3 modes of SSL, and because talking
to your database should be highly secured to protect you against man-in-the-middle
attacks, you should always try to use the most secured setting.

### Need some help?

You tried to setup a secured connection, but it does not work? Your container
is not able to find the correct CA certificate?
[Take a look at Solving SSL issues](https://hexdocs.pm/pog/docs/solving-ssl-issues.html)

## History

Previously this library was named `gleam_pgo`. This old name is deprecated and
all future development and support will happen here.
