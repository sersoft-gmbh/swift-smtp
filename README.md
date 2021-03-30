# SwiftSMTP

SwiftSMTP provides a SwiftNIO based implementation for sending emails using SMTP servers.

There is the `Configuration` struct (and its nested structs and enums) that configure the access to a SMTP server (hostname, credentials, ...).

Once you have a `Configuration` (together with an NIO EventLoopGroup), you can create a `Mailer`. The mailer is responsible for setting up the NIO channel that connects to the SMTP server and delivers the email.

With a `Mailer` at your disposal, you can use it to send an `Email`. Since SMTP terminates the connection after each delivery, `Mailer` needs to create a new connection per `Email` that is to be delivered.

To use SwiftSMTP, add the following package dependency:
```swift
.package(url: "https://github.com/sersoft-gmbh/swift-smtp.git", from: "2.0.0")
```

## Usage

The package contains two targets `SwiftSMTP` and `SwiftSMTPVapor`. The former is a pure SwifTNIO implementation, while the latter contains some helpers for using SwiftSMTP in Vapor applications.

### SwiftSMTP

To send an email in SwiftSMTP, first create a `Configuration`. The configuration contains the server parameters (server address, port, credentials, ...).
Once you have a configuration, you can create a `Mailer` with it. You'll also need a SwiftNIO `EventLoopGroup` (e.g. `MultiThreadedEventLoopGroup`).
You then create an `Email` and simply call `send(email:)` on your mailer with it. The returned `EventLoopFuture` will return once the email was successfully sent, or will fail with the error returned from the SMTP server.

#### Creating a `Configuration`

There are multiple ways to create a configuration. The simplest is to use environment variables:

```swift
let configuration = Configuration.fromEnvironment()
```

The following environment variables are read (for more details please also check the header docs):

- `SMTP_HOST`: The hostname to use or `127.0.0.1` if none is set.
- `SMTP_PORT`: The port to use. The encryption's default will be used if not set or not a valid integer.
- `SMTP_ENCRYPTION`: The encyrption to use.
- `SMTP_TIMEOUT`: The connection time out in seconds. If not set or not a valid 64-bit integer, a sensible default.
- `SMTP_USERNAME`: The username to use.
- `SMTP_PASSWORD`: The password to use.

### SwiftSMTPVapor

SwiftSMTPVapor builds on SwiftSMTP and adds some convenience for using it with Vapor. First, you need to configure SwiftSMTPVapor once at startup. This is usually done in `configure(_:)`. There are multiple ways to configure SwiftSMTP here. The simplest is to use environment variables (see above for details on that):

```swift
/// Initialize SwiftSMTP
app.swiftSMTP.initialize(with: .fromEnvironment())
```

Another way to initialize SwiftSMTP is to use the `SMTPInitializer` lifecycle handler:

```swift
/// Initialize SwiftSMTP
app.lifecycle.use(SMTPInitializer(configuration: .fromEnvironment()))
```

The main difference between the two is that with the former, SwiftSMTP is ready to use after the call. The latter will initialize SwiftSMTP during the boot of the Vapor Application. In most cases, this difference doesn't matter and the two are equivalent.

You can of course also provide your own configuration. There are also additional parameters for specifiying the source of the event loop group to use for mailers and whether or not to write transmission logs. Usually, those can be left to their defaults.

Next, you can use SwiftSMTP inside a request:

```swift
func handleRequest(_ request: Request) -> EventLoopFuture<Response> {
    let email: Email // created before
    return request.swiftSMTP.mailer.send(email: email).transform(to: Response())
}
```

This uses the shared mailer, which is lazily initialized. If you need a dedicated mailer, you can use the `createNewMailer` method:

```swift
func handleRequest(_ request: Request) -> EventLoopFuture<Response> {
    let email: Email // created before
    return request.swiftSMTP.createNewMailer().send(email: email).transform(to: Response())
}
```

When using the application's event loop group (which is the default), there will be almost no difference between the two - except maybe for the connection limit. A mailer has a connection limit of two connections by default, which means that a new mailer does not have any connections in its queue.
When using a custom event loop group source, however, creating a new mailer will also create a new event loop group. It's important to keep this in mind, since you're responsible for shutting down that event loop group - whereas SwiftSMTPVapor takes care of shutting down the event loop group of the shared mailer if you use a custom source there.
