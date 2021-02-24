# Client Authenticated TLS

['Client Authenticated TLS'](https://en.wikipedia.org/wiki/Transport_Layer_Security#Client-authenticated_TLS_handshake) is an implementation of the TLS handshake that provides [mutual authentication](https://en.wikipedia.org/wiki/Mutual_authentication) (also known as 2-way authentication) between clients and servers using TLS/SSL client certificates.

Mutual authentication means that a client will only connect to a valid server (as is the case with normal TLS), but also that a server will only allow valid clients to connect.

This makes it useful in situations where only privileged clients should be able to access a web service or RPC endpoint. For example, you might have a public web service that consumes a private web service. If the service that is intended for private use is accessible on the internet, then it needs to be protected.

Today I am going to demonstrate a simple way to protect a Node server with Client Authenticated TLS using a library called CATKeys (of which I am the author).

## CATKeys

CATKeys was created after reading a [blog post by Anders Brownworth](https://engineering.circle.com/https-authorized-certs-with-node-js-315e548354a2) describing how to use OpenSSL to generate the CAs, certs, keys and configuration required to use client certificates to secure HTTPS. It's a great post that is worth a read if you want to understand what is going on behind the scenes.

CATKeys is a simple library that provides authentication with very little effort. It supports HTTPS as well as TLS communication. Generate keys using simple commands, then use CATKeys as a drop in replacement anywhere you have used `https.createServer()`, `https.request()`, `tls.createServer()` or `tls.connect()`.

### Creating a simple Node HTTP server

The following code assumes you have Node

Let's start with a simple http server which we will migrate to CATKeys.

Save the following file as `serve.js`:

```javascript
const http = require('http')

const serve = () => {
  http.createServer(
    (req, res) => {
      const clientCert = req.connection.getPeerCertificate && req.connection.getPeerCertificate()

      res.writeHead(200)
      res.write('connection')
      res.write(clientCert ? ` secured with CATKeys key '${clientCert.subject.CN}'` : ' insecure')
      res.end()
    }
  ).listen(8080)
}

serve()
```

Now let's create a client. Save the following file as `request.js`:

```javascript
const http = require('http')

const request = () => {
  const req = http.request(
    'https://localhost:8080',
    (res) => {
      const data = []

      res.on('data', (chunk) => { data.push(chunk) })
      res.on('end', () => { console.log(data.join('')) })
      res.on('error', console.error)
    }
  )

  req.end()
}

request()
```

Test that the files work. In one terminal start the server:

```
node serve.js
```

And in another, run the request:

```
node request.js
```

You should see the server's response outputted on the terminal:

```
$ node request.js
connection insecure
```

## Migrating to CATkeys

Install CATKeys from NPM:

```
npm i --save catkeys
```

Generate the server and client keys:

```
npx catkeys create-key --keydir catkeys --server
npx catkeys create-key --keydir catkeys
```

The `-k` option specifies the location of the directory to store the keys. The `-s` directive in the first command creates a server key. Server keys always need to be created first as client keys are created from server keys.

CATKeys is simply a wrapper for the `https` and `tls` method for creating servers and making requests. The signatures of the methods exported are the same as those provided by Node. The only difference is that the CATKeys methods are async methods. This means the following changes need to be made:

- `https` should be imported from the `catkeys` library
- `await` should be used with CATKeys methods

After making these changes, the `serve.js` now looks like this:

```javascript
cconst { https } = require('catkeys')

const serve = async () => {
  (await https.createServer(
    (req, res) => {
      const clientCert = req.connection.getPeerCertificate && req.connection.getPeerCertificate()

      res.writeHead(200)
      res.write('connection')
      res.write(clientCert ? ` secured with CATKeys key '${clientCert.subject.CN}'` : ' insecure')
      res.end()
    }
  )).listen(8080)
}

serve()
```

And `request.js`:

```javascript
const { https } = require('catkeys')

const request = async () => {
  const req = await https.request(
    'https://localhost:8080',
    (res) => {
      const data = []

      res.on('data', (chunk) => { data.push(chunk) })
      res.on('end', () => { console.log(data.join('')) })
      res.on('error', console.error)
    }
  )

  req.end()
}

request()
```

Let's start the server and run the client request again:

```
$ node catkeys/request.js
connection secured with CATKeys
```

Currently this is working becuase `server.js` and `request.js` are sharing the same `catkeys` directory in the project root. If they were running on different hosts you would need to create a `catkeys` directory in the client's project root directory and copy the `catkeys/client.catkey` file into it.

## Server names

TLS certificates normally contain server names. When clients connect to a server, the hostname of the server is compared against the name in it's certificate, and an error is thrown if they do not match.

CATKeys uses a slightly different approach. CATKeys checks the server certificate for a special name that is reserved for server keys. This means that the hostname of the server can change to any value and it does not affect the validity of the certificate. The server identity is still validated using the CA stored in the client key.

To see this in effect, try changing the hostname in the `request.js` from `localhost` to `127.0.0.1` and repeating the request.

If you would prefer to check the server name you can must generate a server key and pass in a hostname:

```
npx catkeys create-key --keydir catkeys --server --name myapp.example.com
npx catkeys create-key --keydir catkeys
```

> ⚠️ Note, you need to recreate client keys if you recreate the server key as client keys are created from it

Now you can connect from clients using `myapp.example.com`. Hosting the server on any other hostname will generate an when a client connects.

If you want tell clients to reject those generic, reserver names that are normally present in server keys I mentioned earlier, and only connect to servers with certificate that match their hostname, you can provide the option `catRejectMismatchedHostname: true`:

```javascript
const req = await https.request(
  'https://localhost:8080',
  { catRejectMismatchedHostname: true },
  (res) => {
    …
  }
)
```

## Rejecting clients

It could be that you want to remove access to a client. CATKeys supports this by providing the options `catCheckKeyExists: true` when calling `createServer()`:

```javascript
(await https.createServer(
  { catCheckKeyExists: true },
  (req, res) => {
    …
  }
)).listen(8080)
```

CATKeys will check the `catkeys` key directory to see if the client key is present. If the key is not on disk then the connection will be closed and the request handler will not be called.

## Multiple client keys

If you have an app that connects to multiple CATKeys servers then you would need multiple client keys. If there is only 1 client key then CATKeys will always use that to connect. If there is more than 1 then you will need to define which key to use when connecting:

```javascript
const req1 = await https.request(
    'https://host1.example.com/',
    { catKey: 'client-key-1' }
    (res) => {
      …
    }
)
const req2 = await https.request(
    'https://host2.example.com/',
    { catKey: 'client-key-2' }
    (res) => {
      …
    }
)
```

## Using keys with servers other than Node

CATKeys can be used with servers other than Node. CATKeys key are just TAR archives and a can be expanded. The comprising CAs, certs and keys can be extracted for use with many servers that support TLS/SSL.

Expand the server key we created earlier:

```
npx catkeys extract-key catkeys/server.catkey
```

There will now be a directory `server` in the current directory.

```
$ ls -l server
total 32
-rw-r--r--  1 pommy  staff  2053 24 Feb 19:44 ca-crt.pem
-rw-r--r--  1 pommy  staff  2009 24 Feb 19:44 crt.pem
-rw-r--r--  1 pommy  staff  3243 24 Feb 19:44 key.pem
```

These files can now be used in any web server that supports pem formats.

Eg. Nginx can be configured to request client certificates and proxy to an HTTP upstream server on port 8081 as follows:

```
server {
    listen 8080 ssl;

    ssl_certificate server/crt.pem;
    ssl_certificate_key server/key.pem;
    ssl_client_certificate server/ca-crt.pem;
    ssl_verify_client on;

    location / {
      proxy_pass http://localhost:8081;
    }
  }
```

> ⚠️ The `ssl_verify_client on;` is very important. It validates clients using the ceriticate specified in `ssl_client_certificate` and rejects clients that fail validation.

Because the TLS connection is terminated at the server, you will not be able to use the option `catCheckKeyExists: true` to reject clients without a key present on disk.

## Determining which clients are connecting

Suppose you want to implement access control for different clients, or maybe you just want to log the name of the client that connected to a server. This can be done by accessing `req.connection.getPeerCertificate()` in the request handler on the server:

```javascript
(await https.createServer(
  (req, res) => {
    const clientCert = req.connection.getPeerCertificate()
    console.log('Connection made by client: ' + clientCert.subject.CN)
    …
  }
)).listen(8080)
```

## TLS

We have only covered CATKeys with HTTPS, but it can also support communication over TLS upgraded sockets. This is useful for real-time communication. I am not going to dive into how to use `tls.createServer()` and `tls.connect()` in this guide as they have the same signature as they do in Node's `tls` module, with the difference again being that they are `async` methods. The `cat*` options we have reviewed apply to them just as they did for the `https` methods.

The CATKeys documentation includes examples for creating a [plain TLS server and client](https://github.com/93million/catkeys/tree/master/examples/tls) and also [for use with JsonSocket](https://github.com/93million/catkeys/tree/master/examples/json-socket) - which allows for sending complex structures using JSON over a TLS connection.

## That's all folks

Hopefully that gives you an idea of how to implement client authenticated TLS using CATKeys. Did I miss anything or confuse you? Don't hesitate to post questions and suggestions in the comments.
