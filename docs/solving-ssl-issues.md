# Solving SSL issues

Talking to your database should always be secured (if possible), because it's one
of the most sensible operation in your daily production setup. As such, a lot of
Postgres databases are secured through SSL. Most of the time, managed instances of
Postgres require you to use an SSL connection. But finding the correct SSL setup
can be hard, because it ask you to have some knowledge on how SSL and your OS
works under-the-hood.

That guide is here to help you setup correctly your database connection.

## Understanding SSL/TLS connections

An SSL/TLS connection is different from a plain connection by its nature: when with
plain connections, you just send the bits on the wire in a public way (so anybody
can see what bits transit in the network), SSL/TLS connections encrypt every bits
between you and the server. It means nobody can see what you're exchanging with
the server. Of course, this is a requirement when you're dealing with sensible
data (password, health data, etc.), but it's also becoming the standard when
browsing the web those days.

SSL/TLS connections rely on [asymmetric encryption](https://en.wikipedia.org/wiki/Public-key_cryptography).
When you're talking to a secured server, your client will ask for the public SSL
certificate, containing the public key, and will try to see if it has been issued by
a well-known, certified authority. If everything went well, the client can continue,
and will generate some session keys to talk with the server. After that process,
your connection will be 100% encrypted, and impossible to understand for the rest
of the world.

### Solving the CA certificate OS issue

However, sometimes, CA certificates can be missing. While OS maintains a list of
CA certificates to simplify the life of every users, the CA certificate used by
your server can be a _self signed certificate_ for example. It means, even if
it's properly secured, everyone will have an error, rejecting because the CA
certificate can not be verified.

To make sure your error comes from an CA certificate issue, it's recommended to
first test your connection in `pog` with `ssl: pog.SslUnverified`. Because of the
nature of the setting, if the only error comes from SSL, it should work directly.
If it does not work, your problem comes from something else.

In such case, it's required to provide the correct CA certificates to the client.
`pog` tries to solve the problem in an elegant way. Instead of having to
grab the certificate and handle it in your application code, `pog` will
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
`/etc/ssl/certs/ca-certificates.crt`. A simple `cat my-certificates.pem >> /etc/ssl/certs/ca-certificates.crt`
will do the trick! Be careful though, everytime the OS will
run `update-ca-certificates` by itself, you'll have to redo the operation. In such
cases, it's recommended to add the certificates in `/usr/local/share/ca-certificates`,
but it could be useful in case you're building a Docker image for example!

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

#### An example with Docker?

Dockerfiles often rely on Alpine, which does not includes CA certificates by default.
Some providers, like AWS, will also self-sign CA certificates. In that case, it's
up to you to provide the correct certificate. Here's an example of some Docker
steps to provide the correct certificate.

```dockerfile
# Update your package manager.
RUN apt update
# Add the main CA certificates.
RUN apt install -y ca-certificates inotify-tools curl
# Get the latest CA certificates.
RUN update-ca-certificates
# Get the certificate form AWS.
RUN mkdir -p /aws-certificates
RUN curl -o /aws-certificates/rds.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
# Provide the CA certificate in the OS directly.
RUN cat /aws-certificates/rds.pem >> /etc/ssl/certs/ca-certificates.crt
```
