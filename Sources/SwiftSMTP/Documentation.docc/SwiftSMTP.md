# ``SwiftSMTP``

A Swift NIO based implementation for sending emails via SMTP servers.

## Installation

To use SwiftSMTP, add the following package dependency:
```swift
.package(url: "https://github.com/sersoft-gmbh/swift-smtp", from: "2.0.0"),
```

## Usage

To send an email in SwiftSMTP, first create a ``Configuration``. The configuration contains the server parameters (server address, port, credentials, ...).
Next you can create a ``Mailer`` with it. You'll also need a SwiftNIO `EventLoopGroup` (e.g. `MultiThreadedEventLoopGroup`).
You then create an ``Email`` and simply call ``Mailer/send(_:)->_`` on your mailer with it. The returned `EventLoopFuture` will return once the email was successfully sent, or will fail with the error returned from the SMTP server.

### Creating a `Configuration`

There are multiple ways to create a configuration. The simplest is to use environment variables:

```swift
let configuration = Configuration.fromEnvironment()
```

The following environment variables are read (for more details please also check the header docs):

- `SMTP_HOST`: The hostname / ip to use or `127.0.0.1` if none is set.
- `SMTP_PORT`: The port to use. The encryption's default will be used if not set or not a valid integer.
- `SMTP_ENCRYPTION`: The encyrption to use.
- `SMTP_TIMEOUT`: The connection time out in seconds. If not set or not a valid 64-bit integer, a sensible default is used.
- `SMTP_USERNAME`: The username to use.
- `SMTP_PASSWORD`: The password to use.
- `SMTP_USE_ESMTP`: If set to `1`, ESMTP will be used (e.g. send `EHLO` instead of just `HELO`).

You can also create a configuration partially from the environment. Each sub-object of ``Configuration`` has it's own `.fromEnvironment()` method. Of course you can also create the configuration completely without any environment values.

### Creating a `Mailer`

Once you have a ``Configuration``, you can use it to create a ``Mailer`` (together with an `EventLoopGroup`):

```swift
let configuration = Configuration.fromEnvironment() // or one you created manually
let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
let mailer = Mailer(group: elg, configuration: configuration)
```

You can then use ``Mailer/send(_:)->_`` to send ``Email``s:

```swift
let email: Email // created previously 
let future = mailer.send(email)
```

SwiftSMTP also works with Swift concurrency:

```swift
let email: Email // created previously
try await mailer.send(email)
```
