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

## SSL options and CA Certificates

`gleam_pgo` supports two main modes of SSL: `SslEnabled` and `SslVerify`. The
latter is the most secured form of SSL, checking every signatures against the
system-wide CA certificates provided by the OS.

You can easily enable one or the other using `ssl: SslEnabled` or
`ssl: SslDisabled` in `pgo.Config`. `sslmode` is also supported in configuration
URI. The different values allowed are `disable`, `require`, `verify-ca` and
`verify-full` (as specified in Postgres documentation).

Below a little bit more explanations on SSL if you need to understand better
what's happening, and some common problems.

### A word on SSL connections

Every SSL connection should be setup using an SSL certificate. An SSL certificate
is notably made of a signature of a Certificate Authority (CA), and a public key.
Those two parts allow to establish the secured connection as well as checking
the validity of the certificate. When opening a connection with a server secured
with SSL, the server will send the certificate, and every data will be
subsequently sent encrypted with a private key that can be decrypted using the
public key of the certificate. However, we cannot trust a certificate, because an
attacker can create a certificate on its own. That's where the signature comes into
play: the signature of the CA cannot be easily compromised. When a client
receives an SSL certificate, it will first check the CA signature against a list
of known authorities, and if one of them match, it means the SSL certificate
can be trusted.

### What does it mean for Postgres?

Therefore, it's possible to use an SSL connection with different modes:
accepting SSL, but skipping verification of CA certificate, and accepting
SSL _and_ verifying CA certificate. Most of the time and when in critical
environment, you should _always_ verify the CA certificate. However, some
situations can ask to disable that layer of security, mainly because of
self-issued certificates.

One common situation is when using a managed version of Postgres, for instance
on Digital Ocean or AWS RDS. Those managed services are powerful hosted services
of Postgres, but to avoid spending money on SSL certificates, they prefer issue
their own certificates. It means they created a custom CA certificate, and they
issue SSL certificates for databases with that custom CA certificate. Because
that certificate is not in your default environment, setting a connection with
`SslVerify` _will_ fail, because BEAM will not be able to check the validity of
the certificate. All it will be able to do is guaranteeing the connection is
encrypted with SSL. Switching to `SslEnabled` can suffice, especially if your
instance is secured in your VPC. However, you're still a potential target for a
man-in-the-middle attack.

### Solving the CA certificate issue

To solve the custom CA certificate problem, what is needed is to provide the CA
certificate itself, to check the SSL certificate of the database against it.
`gleam_pgo` tries to solve the problem in an elegant way. Instead of having to
grab the certificate and handle it in your application code, `gleam_pgo` will
read the certificates from your OS, using Erlang function
`public_key:cacerts_get()`.

#### Adding the custom CA certificate in your OS certificate chain

Adding the CA certificate depends on your OS:

##### Linux

CA certificates are managed through the `ca-certificates` package.
Every common installation of Linux have it already installed, excepted Alpine.
Once the package is installed, you should get the certificates you want to add
in `.pem` format to the system, and put it in `/usr/local/share/ca-certificates`,
with a `.crt` extension. Run `update-ca-certificates` and voilà! Your
certificate is added in the certificate chain!

Be careful though, a PEM file can contains _multiple_ certificates. In that case,
you can simply split the PEM file in multiple CRT files,
[like suggested on ServerFault](https://serverfault.com/questions/391396/how-to-split-a-pem-file),
or you could simply push all certificates in the certificate chain by hand! All
`update-ca-certificates` will do is concatenating certificates in
`/etc/ssl/certs/ca-certificates.crt`. A simple `cat my-certificates.pem >> /etc/ssl/certs/ca-certificates.crt` will do the trick! Be careful though, everytime the OS will
run `update-ca-certificates` by itself, you'll have to redo the operation. In such
cases, it's recommended to add the certificates in `/usr/local/share/ca-certificates`,
but it could be useful in case you building a Docker image for example!

##### macOS

CA certificates can simply be added on the system using the keychain! Double-click
on the certificates, and let macOS work for you!

##### \[Reminder\] Shape of a PEM certificate

A PEM certificate looks like this: (example taken from an AWS `eu-west-1` certificate)

```
-----BEGIN CERTIFICATE-----
MIIEBjCCAu6gAwIBAgIJAMc0ZzaSUK51MA0GCSqGSIb3DQEBCwUAMIGPMQswCQYD
VQQGEwJVUzEQMA4GA1UEBwwHU2VhdHRsZTETMBEGA1UECAwKV2FzaGluZ3RvbjEi
MCAGA1UECgwZQW1hem9uIFdlYiBTZXJ2aWNlcywgSW5jLjETMBEGA1UECwwKQW1h
em9uIFJEUzEgMB4GA1UEAwwXQW1hem9uIFJEUyBSb290IDIwMTkgQ0EwHhcNMTkw
ODIyMTcwODUwWhcNMjQwODIyMTcwODUwWjCBjzELMAkGA1UEBhMCVVMxEDAOBgNV
BAcMB1NlYXR0bGUxEzARBgNVBAgMCldhc2hpbmd0b24xIjAgBgNVBAoMGUFtYXpv
biBXZWIgU2VydmljZXMsIEluYy4xEzARBgNVBAsMCkFtYXpvbiBSRFMxIDAeBgNV
BAMMF0FtYXpvbiBSRFMgUm9vdCAyMDE5IENBMIIBIjANBgkqhkiG9w0BAQEFAAOC
AQ8AMIIBCgKCAQEArXnF/E6/Qh+ku3hQTSKPMhQQlCpoWvnIthzX6MK3p5a0eXKZ
oWIjYcNNG6UwJjp4fUXl6glp53Jobn+tWNX88dNH2n8DVbppSwScVE2LpuL+94vY
0EYE/XxN7svKea8YvlrqkUBKyxLxTjh+U/KrGOaHxz9v0l6ZNlDbuaZw3qIWdD/I
6aNbGeRUVtpM6P+bWIoxVl/caQylQS6CEYUk+CpVyJSkopwJlzXT07tMoDL5WgX9
O08KVgDNz9qP/IGtAcRduRcNioH3E9v981QO1zt/Gpb2f8NqAjUUCUZzOnij6mx9
McZ+9cWX88CRzR0vQODWuZscgI08NvM69Fn2SQIDAQABo2MwYTAOBgNVHQ8BAf8E
BAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUc19g2LzLA5j0Kxc0LjZa
pmD/vB8wHwYDVR0jBBgwFoAUc19g2LzLA5j0Kxc0LjZapmD/vB8wDQYJKoZIhvcN
AQELBQADggEBAHAG7WTmyjzPRIM85rVj+fWHsLIvqpw6DObIjMWokpliCeMINZFV
ynfgBKsf1ExwbvJNzYFXW6dihnguDG9VMPpi2up/ctQTN8tm9nDKOy08uNZoofMc
NUZxKCEkVKZv+IL4oHoeayt8egtv3ujJM6V14AstMQ6SwvwvA93EP/Ug2e4WAXHu
cbI1NAbUgVDqp+DRdfvZkgYKryjTWd/0+1fS8X1bBZVWzl7eirNVnHbSH2ZDpNuY
0SBd8dj5F6ld3t58ydZbrTHze7JJOd8ijySAp4/kiu9UfZWuTPABzDa/DSdz9Dk/
zPW4CXXvhLmE02TA9/HeCw3KEHIwicNuEfw=
-----END CERTIFICATE-----
```
